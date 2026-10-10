//
//  VaultKeyRuleTests.swift
//  VaultCoreTests
//
//  Created by Inez Amanda on 4/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Crypto
import Foundation
import Testing

@testable import VaultCore

/// A new vault key is created only when the key store says the key does not exist. Any
/// other error means it exists but is locked: surface it, create nothing.
@Suite("Vault key rule")
struct VaultKeyRuleTests {
    static let lockedFailures: [InMemoryKeyStore.ReadFailure] = [.locked, .interactionNotAllowed, .unexpected]

    /// The Keychain status the app needs; nil for errors that are not Keychain errors.
    static func expectedError(_ failure: InMemoryKeyStore.ReadFailure) -> VaultError {
        switch failure {
        case .locked: .vaultKeyUnavailable(status: -25293)
        case .interactionNotAllowed: .vaultKeyUnavailable(status: -25308)
        case .unexpected: .vaultKeyUnavailable(status: nil)
        }
    }

    @Test func newVaultCreatesKeyOnlyWhenNotFound() async throws {
        let vault = try TestVault()
        let report = try await vault.makeStore().open()
        #expect(report.createdVault)
        #expect(await vault.keyStore.createCount == 1)
        #expect(await vault.keyStore.key(for: try vault.header().vaultId) != nil)
    }

    @Test(arguments: lockedFailures)
    func lockedKeyStoreNeverCreatesANewVault(_ failure: InMemoryKeyStore.ReadFailure) async throws {
        let vault = try TestVault()
        await vault.keyStore.setReadFailure(failure)
        await #expect(throws: Self.expectedError(failure)) { try await vault.makeStore().open() }
        #expect(await vault.keyStore.createCount == 0)
        #expect(try vault.allFiles().isEmpty)  // nothing written
    }

    @Test(arguments: lockedFailures)
    func lockedKeyStoreNeverReplacesAnExistingKey(_ failure: InMemoryKeyStore.ReadFailure) async throws {
        let vault = try TestVault()
        let store = vault.makeStore()
        try await store.open()
        let id = try await store.createDocument(
            type: .ktp, expiry: nil, pinned: false,
            fields: Synthetic.ktpFields, pages: [Synthetic.page("k")])
        let header = try vault.header()
        let key = try #require(await vault.keyStore.key(for: header.vaultId))
        let filesBefore = try vault.allFiles().map { try Data(contentsOf: $0) }

        await vault.keyStore.setReadFailure(failure)
        await #expect(throws: Self.expectedError(failure)) { try await vault.makeStore().open() }
        #expect(await vault.keyStore.createCount == 1)
        #expect(bytes(try #require(await vault.keyStore.key(for: header.vaultId))) == bytes(key))
        #expect(try vault.header() == header)
        #expect(try vault.allFiles().map { try Data(contentsOf: $0) } == filesBefore)

        // Once the key store unlocks again, everything is still there.
        await vault.keyStore.setReadFailure(nil)
        let reopened = vault.makeStore()
        try await reopened.open()
        #expect(try await reopened.fields(of: id) == Synthetic.ktpFields)
    }

    static let createFailures: [InMemoryKeyStore.CreateFailure] = [.status(-25291), .alreadyExists]

    @Test(arguments: createFailures)
    func failedKeyCreationWritesNothing(_ failure: InMemoryKeyStore.CreateFailure) async throws {
        // For example a phone with no passcode: the read says "not found", then adding the
        // .userPresence item fails. No vault may be created without its key.
        let vault = try TestVault()
        await vault.keyStore.setCreateFailure(failure)
        let expected: VaultError =
            switch failure {
            case .status(let status): .vaultKeyUnavailable(status: status)
            case .alreadyExists: .vaultKeyUnavailable(status: nil)
            }
        await #expect(throws: expected) { try await vault.makeStore().open() }
        #expect(await vault.keyStore.createCount == 1)
        #expect(!FileManager.default.fileExists(atPath: vault.root.path))
        #expect(try vault.allFiles().isEmpty)
    }

    @Test func existingVaultWithMissingKeyIsNotRecreated() async throws {
        let vault = try TestVault()
        let store = vault.makeStore()
        try await store.open()
        _ = try await store.createDocument(
            type: .ktp, expiry: nil, pinned: false,
            fields: Synthetic.ktpFields, pages: [Synthetic.page("k")])
        let header = try vault.header()
        await vault.keyStore.setKey(nil, for: header.vaultId)

        await #expect(throws: VaultError.vaultKeyMissing) { try await vault.makeStore().open() }
        #expect(await vault.keyStore.createCount == 1)
        #expect(await vault.keyStore.key(for: header.vaultId) == nil)
        #expect(try vault.header() == header)
    }
}
