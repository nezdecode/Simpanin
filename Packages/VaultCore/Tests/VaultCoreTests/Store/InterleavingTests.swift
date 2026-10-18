//
//  InterleavingTests.swift
//  VaultCoreTests
//
//  Created by Inez Amanda on 13/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Crypto
import Foundation
import Testing

@testable import VaultCore

/// VaultStore only waits on the key store. While it waits, other calls to the actor run,
/// so each wait is tested with the calls that could land in it.
@Suite("Calls that overlap")
struct InterleavingTests {
    func makeStore(_ vault: TestVault, _ keyStore: GatedKeyStore) -> VaultStore {
        VaultStore(
            rootDirectory: vault.root, projectionURL: vault.projectionURL, keyStore: keyStore,
            clock: vault.clock, fileProtector: NoFileProtection())
    }

    @Test func lockWhileOpenWaitsForTheKeyLeavesTheVaultLocked() async throws {
        // The phone locks while the Face ID prompt is up.
        let vault = try TestVault()
        try await vault.makeStore().open()
        let keyStore = GatedKeyStore(vault.keyStore)
        let store = makeStore(vault, keyStore)
        let opening = Task { try await store.open() }
        await keyStore.waitForCalls()

        await store.lock()
        await keyStore.release()
        await #expect(throws: VaultError.locked) { try await opening.value }
        await #expect(throws: VaultError.locked) { try await store.documents() }

        // Nothing is stuck: the next open works.
        try await store.open()
        #expect(try await store.documents().isEmpty)
    }

    @Test func lockWhileANewVaultIsCreatedKeepsTheVault() async throws {
        let vault = try TestVault()
        let keyStore = GatedKeyStore(vault.keyStore)
        let store = makeStore(vault, keyStore)
        let opening = Task { try await store.open() }
        await keyStore.waitForCalls()

        await store.lock()
        await keyStore.release()
        await #expect(throws: VaultError.locked) { try await opening.value }

        // The key and vault.json were already written, so the next open finds the same vault.
        let report = try await vault.makeStore().open()
        #expect(!report.createdVault)
        #expect(await vault.keyStore.createCount == 1)
    }
    @Test func quarantineWhileOpenWaitsWritesNothingAfterwards() async throws {
        // quarantineVault waits for an open in progress, but a new open can start before it
        // resumes. Then it locks and moves the folder while that open waits for the key.
        // The test does those two steps itself, because the real call would wait at the gate.
        let vault = try TestVault()
        try await vault.makeStore().open()
        let keyStore = GatedKeyStore(vault.keyStore)
        let store = makeStore(vault, keyStore)
        let opening = Task { try await store.open() }
        await keyStore.waitForCalls()

        await store.lock()
        let moved = vault.base.appending(path: "Moved", directoryHint: .isDirectory)
        try FileManager.default.moveItem(at: vault.root, to: moved)
        await keyStore.release()
        await #expect(throws: VaultError.locked) { try await opening.value }
        #expect(!FileManager.default.fileExists(atPath: vault.root.path))  // no empty Vault/pages/
    }

    @Test func deletingTheSameQuarantinedVaultTwiceSucceedsOnce() async throws {
        // A double tap on "delete": both calls wait for the key store at the same time.
        let vault = try TestVault()
        try await vault.makeStore().open()
        let oldID = try vault.header().vaultID
        let keyStore = GatedKeyStore(vault.keyStore)
        let store = makeStore(vault, keyStore)
        let folder = try #require(try await store.quarantineVault(to: vault.quarantineURL))
        let entry = try #require(try await store.quarantinedVaults(in: vault.quarantineURL).vaults.first)

        let first = Task { try await store.deleteQuarantinedVault(entry) }
        let second = Task { try await store.deleteQuarantinedVault(entry) }
        await keyStore.waitForCalls(2)
        await keyStore.release()
        try await first.value
        try await second.value
        #expect(!FileManager.default.fileExists(atPath: folder.path))
        #expect(await vault.keyStore.key(for: oldID) == nil)
    }
}

/// Holds every key store call at a gate until the test calls `release()`, like a Face ID
/// prompt that is still on screen. Lets a test run other calls while `open()` waits.
actor GatedKeyStore: KeyStore {
    let inner: InMemoryKeyStore
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private var isReleased = false
    private(set) var callsStarted = 0

    init(_ inner: InMemoryKeyStore) { self.inner = inner }

    func release() {
        isReleased = true
        for continuation in waiting { continuation.resume() }
        waiting = []
    }

    /// Returns once `count` calls are waiting at the gate (or have passed it).
    func waitForCalls(_ count: Int = 1) async {
        while callsStarted < count { await Task.yield() }
    }

    private func gate() async {
        callsStarted += 1
        if !isReleased { await withCheckedContinuation { waiting.append($0) } }
    }

    func readVaultKey(for vaultID: VaultID) async throws -> SymmetricKey {
        await gate()
        return try await inner.readVaultKey(for: vaultID)
    }

    func createVaultKey(for vaultID: VaultID) async throws -> SymmetricKey {
        await gate()
        return try await inner.createVaultKey(for: vaultID)
    }

    func deleteVaultKey(for vaultID: VaultID) async throws {
        await gate()
        try await inner.deleteVaultKey(for: vaultID)
    }
}
