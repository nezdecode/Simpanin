//
//  QuarantineTests.swift
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

/// "Mulai vault baru". `quarantineVault(to:)` moves the vault folder aside unchanged, then
/// `open()` creates a new vault. Also covers listing and deleting quarantined vaults.
@Suite("Quarantine")
struct QuarantineTests {
    /// 2026-10-04 13:05:09 UTC
    static let resetTime = Date(timeIntervalSince1970: 1_791_119_109)

    struct Setup {
        let vault: TestVault
        let oldHeader: VaultHeader
        let oldKey: SymmetricKey
        let oldFiles: [String: Data]
        let documentID: DocumentID
    }

    func makeVault() async throws -> Setup {
        let vault = try TestVault(clock: TestClock(Self.resetTime - 3600))
        let store = vault.makeStore()
        try await store.open()
        let id = try await store.createDocument(
            type: .ktp, expiry: nil, pinned: false,
            fields: Synthetic.ktpFields, pages: [Synthetic.page("ktp")])
        let header = try vault.header()
        let key = try #require(await vault.keyStore.key(for: header.vaultId))
        vault.clock.set(Self.resetTime)
        return Setup(
            vault: vault, oldHeader: header, oldKey: key,
            oldFiles: try TestVault.files(in: vault.root), documentID: id)
    }

    /// The old files are intact at `quarantined`, and opening created an empty vault with a new id.
    func expectFreshVault(_ setup: Setup, _ store: VaultStore, quarantined: URL?) async throws {
        let moved = try #require(quarantined)
        #expect(try TestVault.files(in: moved) == setup.oldFiles)
        let header = try setup.vault.header()
        #expect(header.vaultId != setup.oldHeader.vaultId)
        #expect(try await store.documents().isEmpty)
        #expect(try await store.recentlyDeleted().isEmpty)
        #expect(try setup.vault.projection().documents.isEmpty)
        #expect(await setup.vault.keyStore.key(for: header.vaultId) != nil)
    }

    // MARK: Moving the vault aside

    @Test func quarantineThenOpenAfterMissingKey() async throws {
        let setup = try await makeVault()
        await setup.vault.keyStore.setKey(nil, for: setup.oldHeader.vaultId)
        let store = setup.vault.makeStore()
        await #expect(throws: VaultError.vaultKeyMissing) { try await store.open() }

        let moved = try await store.quarantineVault(to: setup.vault.quarantineURL)
        #expect(moved?.lastPathComponent == "20261004-130509")
        #expect(moved?.deletingLastPathComponent().standardizedFileURL == setup.vault.quarantineURL.standardizedFileURL)
        #expect(!FileManager.default.fileExists(atPath: setup.vault.root.path))
        try await store.open()
        try await expectFreshVault(setup, store, quarantined: moved)
        #expect(await setup.vault.keyStore.createCount == 2)
    }

    @Test func quarantineKeepsOldKeyAndFilesRecoverable() async throws {
        let setup = try await makeVault()
        let wrongKey = VaultCrypto.newKey()
        await setup.vault.keyStore.setKey(wrongKey, for: setup.oldHeader.vaultId)
        let store = setup.vault.makeStore()
        await #expect(throws: VaultError.vaultUnreadable) { try await store.open() }

        let moved = try #require(try await store.quarantineVault(to: setup.vault.quarantineURL))
        try await store.open()
        try await expectFreshVault(setup, store, quarantined: moved)
        // The old Keychain item is left exactly as it was.
        #expect(bytes(try #require(await setup.vault.keyStore.key(for: setup.oldHeader.vaultId))) == bytes(wrongKey))

        // With the right key, the quarantined vault still opens with its documents.
        let later = try TestVault(clock: TestClock(Self.resetTime))
        try FileManager.default.copyItem(at: moved, to: later.root)
        await later.keyStore.setKey(setup.oldKey, for: setup.oldHeader.vaultId)
        let restored = later.makeStore()
        try await restored.open()
        #expect(try await restored.fields(of: setup.documentID) == Synthetic.ktpFields)
        #expect(try await restored.pages(of: setup.documentID).map(\.data) == [Synthetic.page("ktp")])
    }

    @Test func openingFailsAfterTheMoveButTheAppKnowsWhereTheOldVaultIs() async throws {
        // The key store is locked when the new vault is opened.
        let setup = try await makeVault()
        let store = setup.vault.makeStore()
        let moved = try #require(try await store.quarantineVault(to: setup.vault.quarantineURL))
        await setup.vault.keyStore.setReadFailure(.locked)

        await #expect(throws: VaultError.vaultKeyUnavailable(status: -25293)) { try await store.open() }
        #expect(try TestVault.files(in: moved) == setup.oldFiles)
        #expect(!FileManager.default.fileExists(atPath: setup.vault.root.path))  // no half-made vault
        #expect(await setup.vault.keyStore.createCount == 1)

        // Once the key store unlocks, open() creates the new vault.
        await setup.vault.keyStore.setReadFailure(nil)
        try await store.open()
        try await expectFreshVault(setup, store, quarantined: moved)
    }

    @Test func existingQuarantineNamesGetASuffix() async throws {
        let setup = try await makeVault()
        let fileManager = FileManager.default
        for name in ["20261004-130509", "20261004-130509-2"] {
            let dir = setup.vault.quarantineURL.appending(path: name, directoryHint: .isDirectory)
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data(name.utf8).write(to: dir.appending(path: "marker"))
        }
        let store = setup.vault.makeStore()
        let moved = try await store.quarantineVault(to: setup.vault.quarantineURL)
        #expect(moved?.lastPathComponent == "20261004-130509-3")
        try await store.open()
        try await expectFreshVault(setup, store, quarantined: moved)
        for name in ["20261004-130509", "20261004-130509-2"] {
            let marker = setup.vault.quarantineURL.appending(path: "\(name)/marker")
            #expect(try Data(contentsOf: marker) == Data(name.utf8))
        }
    }

    @Test func folderNameIsUTCNotLocalTime() async throws {
        // 20:30 UTC on 4 Oct is already 5 Oct in Jakarta (UTC+7).
        let setup = try await makeVault()
        setup.vault.clock.set(Date(timeIntervalSince1970: 1_791_145_800))
        let moved = try await setup.vault.makeStore().quarantineVault(to: setup.vault.quarantineURL)
        #expect(moved?.lastPathComponent == "20261004-203000")
    }

    @Test func nothingToQuarantineReturnsNil() async throws {
        let vault = try TestVault(clock: TestClock(Self.resetTime))
        let store = vault.makeStore()
        #expect(try await store.quarantineVault(to: vault.quarantineURL) == nil)
        #expect(!FileManager.default.fileExists(atPath: vault.quarantineURL.path))
    }

    @Test func quarantiningAnOpenVaultLocksTheStore() async throws {
        let setup = try await makeVault()
        let store = setup.vault.makeStore()
        try await store.open()
        let moved = try await store.quarantineVault(to: setup.vault.quarantineURL)
        await #expect(throws: VaultError.locked) { try await store.documents() }
        try await store.open()
        try await expectFreshVault(setup, store, quarantined: moved)
        await #expect(throws: VaultError.documentNotFound) { try await store.fields(of: setup.documentID) }
    }

    // MARK: Listing and deleting ("Data lama")

    struct TwoQuarantines {
        let setup: Setup
        let store: VaultStore
        let first: URL
        let second: URL
        let secondID: VaultID
    }

    /// Two quarantined vaults, the first one still with its key, and a new live vault.
    func makeTwoQuarantines() async throws -> TwoQuarantines {
        let setup = try await makeVault()
        let store = setup.vault.makeStore()
        let first = try #require(try await store.quarantineVault(to: setup.vault.quarantineURL))
        try await store.open()
        _ = try await store.createDocument(
            type: .sim, expiry: nil, pinned: false,
            fields: Synthetic.simFields, pages: [Synthetic.page("sim")])
        let secondID = try setup.vault.header().vaultId
        setup.vault.clock.advance(by: 60)
        let second = try #require(try await store.quarantineVault(to: setup.vault.quarantineURL))
        try await store.open()
        return TwoQuarantines(setup: setup, store: store, first: first, second: second, secondID: secondID)
    }

    func size(of folder: URL) throws -> Int64 {
        Int64(try TestVault.files(in: folder).values.reduce(0) { $0 + $1.count })
    }

    @Test func listsQuarantinedVaultsAndReportsUnreadableFolders() async throws {
        let quarantines = try await makeTwoQuarantines()
        let fileManager = FileManager.default
        let garbled = quarantines.setup.vault.quarantineURL.appending(
            path: "20261004-140000", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: garbled, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: garbled.appending(path: "vault.json"))
        let empty = quarantines.setup.vault.quarantineURL.appending(
            path: "20261004-150000", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: empty, withIntermediateDirectories: true)
        try Data("stray".utf8).write(to: quarantines.setup.vault.quarantineURL.appending(path: "notes.txt"))
        let before = try TestVault.files(in: quarantines.setup.vault.quarantineURL)

        let listing = try await quarantines.store.quarantinedVaults(in: quarantines.setup.vault.quarantineURL)
        #expect(listing.vaults.map(\.vaultID) == [quarantines.setup.oldHeader.vaultId, quarantines.secondID])
        #expect(
            listing.vaults.map { $0.folder.standardizedFileURL }
                == [quarantines.first, quarantines.second].map(\.standardizedFileURL))
        #expect(
            listing.vaults.map(\.sizeInBytes) == [try size(of: quarantines.first), try size(of: quarantines.second)])
        #expect(
            listing.unreadableFolders.map { $0.standardizedFileURL } == [garbled, empty].map(\.standardizedFileURL))
        #expect(try TestVault.files(in: quarantines.setup.vault.quarantineURL) == before)  // listing touches nothing
    }

    @Test func listingAMissingQuarantineFolderIsEmpty() async throws {
        let vault = try TestVault()
        let listing = try await vault.makeStore().quarantinedVaults(in: vault.quarantineURL)
        #expect(listing == QuarantineListing(vaults: [], unreadableFolders: []))
    }

    @Test func deletesAQuarantinedVaultWithItsKey() async throws {
        let quarantines = try await makeTwoQuarantines()
        let liveFiles = try TestVault.files(in: quarantines.setup.vault.root)
        let secondFiles = try TestVault.files(in: quarantines.second)
        let listing = try await quarantines.store.quarantinedVaults(in: quarantines.setup.vault.quarantineURL)

        try await quarantines.store.deleteQuarantinedVault(listing.vaults[0])
        #expect(!FileManager.default.fileExists(atPath: quarantines.first.path))
        #expect(await quarantines.setup.vault.keyStore.key(for: quarantines.setup.oldHeader.vaultId) == nil)
        // The other quarantine, its key and the live vault are untouched.
        #expect(try TestVault.files(in: quarantines.second) == secondFiles)
        #expect(await quarantines.setup.vault.keyStore.key(for: quarantines.secondID) != nil)
        #expect(try TestVault.files(in: quarantines.setup.vault.root) == liveFiles)
        #expect(
            try await quarantines.store.quarantinedVaults(in: quarantines.setup.vault.quarantineURL).vaults.map(
                \.vaultID) == [quarantines.secondID])
    }

    @Test func deletingWhenTheKeyIsAlreadyGoneStillRemovesTheFolder() async throws {
        let quarantines = try await makeTwoQuarantines()
        await quarantines.setup.vault.keyStore.setKey(nil, for: quarantines.setup.oldHeader.vaultId)
        let listing = try await quarantines.store.quarantinedVaults(in: quarantines.setup.vault.quarantineURL)
        try await quarantines.store.deleteQuarantinedVault(listing.vaults[0])
        #expect(!FileManager.default.fileExists(atPath: quarantines.first.path))
    }

    @Test func failedKeyDeletionKeepsTheFolder() async throws {
        let quarantines = try await makeTwoQuarantines()
        let files = try TestVault.files(in: quarantines.first)
        let listing = try await quarantines.store.quarantinedVaults(in: quarantines.setup.vault.quarantineURL)
        await quarantines.setup.vault.keyStore.setDeleteFailure(status: -25308)
        await #expect(throws: VaultError.vaultKeyUnavailable(status: -25308)) {
            try await quarantines.store.deleteQuarantinedVault(listing.vaults[0])
        }
        #expect(try TestVault.files(in: quarantines.first) == files)  // retry is possible from "Data lama"
    }

    @Test func refusesAFolderWhoseVaultFileChanged() async throws {
        let quarantines = try await makeTwoQuarantines()
        let listing = try await quarantines.store.quarantinedVaults(in: quarantines.setup.vault.quarantineURL)
        try Data("not json".utf8).write(to: quarantines.first.appending(path: "vault.json"))
        let files = try TestVault.files(in: quarantines.first)
        await #expect(throws: VaultError.quarantineUnreadable) {
            try await quarantines.store.deleteQuarantinedVault(listing.vaults[0])
        }
        #expect(try TestVault.files(in: quarantines.first) == files)
        #expect(await quarantines.setup.vault.keyStore.key(for: quarantines.setup.oldHeader.vaultId) != nil)
        #expect(await quarantines.setup.vault.keyStore.deleteCount == 0)
    }

    @Test func refusesAnEntryThatNamesAnotherVault() async throws {
        let quarantines = try await makeTwoQuarantines()
        let listing = try await quarantines.store.quarantinedVaults(in: quarantines.setup.vault.quarantineURL)
        let mismatched = QuarantinedVault(
            vaultID: quarantines.secondID, folder: listing.vaults[0].folder,
            sizeInBytes: listing.vaults[0].sizeInBytes)
        await #expect(throws: VaultError.quarantineUnreadable) {
            try await quarantines.store.deleteQuarantinedVault(mismatched)
        }
        #expect(FileManager.default.fileExists(atPath: quarantines.first.path))
        #expect(await quarantines.setup.vault.keyStore.deleteCount == 0)
    }

    @Test func refusesTheVaultInUse() async throws {
        // A copy of the live vault inside Quarantine/ must never cost the live vault its key.
        let quarantines = try await makeTwoQuarantines()
        let liveID = try quarantines.setup.vault.header().vaultId
        let copy = quarantines.setup.vault.quarantineURL.appending(path: "20261004-160000", directoryHint: .isDirectory)
        try FileManager.default.copyItem(at: quarantines.setup.vault.root, to: copy)
        let entry = try #require(
            try await quarantines.store.quarantinedVaults(in: quarantines.setup.vault.quarantineURL)
                .vaults.first { $0.vaultID == liveID })

        await #expect(throws: VaultError.quarantineInUse) { try await quarantines.store.deleteQuarantinedVault(entry) }
        #expect(FileManager.default.fileExists(atPath: copy.path))
        #expect(await quarantines.setup.vault.keyStore.key(for: liveID) != nil)
        #expect(await quarantines.setup.vault.keyStore.deleteCount == 0)
    }
}
