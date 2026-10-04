import Crypto
import Foundation
import Testing
@testable import VaultCore

/// "Mulai vault baru" (design doc, "Recovery screens and quarantine"): `quarantineVault(to:)`
/// moves the whole vault folder to Quarantine/<yyyyMMdd-HHmmss in UTC>/, unchanged, and returns
/// it; `open()` is a separate call that creates the new vault. Nothing is deleted and the old
/// Keychain item is untouched. VaultCore also lists quarantined vaults and deletes one together
/// with its Keychain item.
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
        let id = try await store.createDocument(type: .ktp, expiry: nil, pinned: false,
                                                fields: Synthetic.ktpFields, pages: [Synthetic.page("ktp")])
        let header = try vault.header()
        let key = try #require(await vault.keyStore.key(for: header.vaultId))
        vault.clock.set(Self.resetTime)
        return Setup(vault: vault, oldHeader: header, oldKey: key,
                     oldFiles: try TestVault.files(in: vault.root), documentID: id)
    }

    /// The old files are intact at `quarantined`; opening created an empty vault with a new id.
    func expectFreshVault(_ s: Setup, _ store: VaultStore, quarantined: URL?) async throws {
        let moved = try #require(quarantined)
        #expect(try TestVault.files(in: moved) == s.oldFiles)
        let header = try s.vault.header()
        #expect(header.vaultId != s.oldHeader.vaultId)
        #expect(try await store.documents().isEmpty)
        #expect(try await store.recentlyDeleted().isEmpty)
        #expect(try s.vault.projection().documents.isEmpty)
        #expect(await s.vault.keyStore.key(for: header.vaultId) != nil)
    }

    // MARK: Moving the vault aside

    @Test func quarantineThenOpenAfterMissingKey() async throws {
        let s = try await makeVault()
        await s.vault.keyStore.setKey(nil, for: s.oldHeader.vaultId)
        let store = s.vault.makeStore()
        await #expect(throws: VaultError.vaultKeyMissing) { try await store.open() }

        let moved = try await store.quarantineVault(to: s.vault.quarantineURL)
        #expect(moved?.lastPathComponent == "20261004-130509")
        #expect(moved?.deletingLastPathComponent().standardizedFileURL == s.vault.quarantineURL.standardizedFileURL)
        #expect(!FileManager.default.fileExists(atPath: s.vault.root.path))
        try await store.open()
        try await expectFreshVault(s, store, quarantined: moved)
        #expect(await s.vault.keyStore.createCount == 2)
    }

    @Test func quarantineKeepsOldKeyAndFilesRecoverable() async throws {
        let s = try await makeVault()
        let wrongKey = VaultCrypto.newKey()
        await s.vault.keyStore.setKey(wrongKey, for: s.oldHeader.vaultId)
        let store = s.vault.makeStore()
        await #expect(throws: VaultError.vaultUnreadable) { try await store.open() }

        let moved = try #require(try await store.quarantineVault(to: s.vault.quarantineURL))
        try await store.open()
        try await expectFreshVault(s, store, quarantined: moved)
        // The old Keychain item is left exactly as it was.
        #expect(bytes(try #require(await s.vault.keyStore.key(for: s.oldHeader.vaultId))) == bytes(wrongKey))

        // With the right key, the quarantined vault still opens with its documents.
        let later = try TestVault(clock: TestClock(Self.resetTime))
        try FileManager.default.copyItem(at: moved, to: later.root)
        await later.keyStore.setKey(s.oldKey, for: s.oldHeader.vaultId)
        let restored = later.makeStore()
        try await restored.open()
        #expect(try await restored.fields(of: s.documentID) == Synthetic.ktpFields)
        #expect(try await restored.pages(of: s.documentID).map(\.data) == [Synthetic.page("ktp")])
    }

    @Test func openingFailsAfterTheMoveButTheAppKnowsWhereTheOldVaultIs() async throws {
        // The review's Q1 case: the key store is locked when the new vault is opened.
        let s = try await makeVault()
        let store = s.vault.makeStore()
        let moved = try #require(try await store.quarantineVault(to: s.vault.quarantineURL))
        await s.vault.keyStore.setReadFailure(.locked)

        await #expect(throws: VaultError.vaultKeyUnavailable(status: -25293)) { try await store.open() }
        #expect(try TestVault.files(in: moved) == s.oldFiles)
        #expect(!FileManager.default.fileExists(atPath: s.vault.root.path))  // no half-made vault
        #expect(await s.vault.keyStore.createCount == 1)

        // Once the key store unlocks, open() creates the new vault.
        await s.vault.keyStore.setReadFailure(nil)
        try await store.open()
        try await expectFreshVault(s, store, quarantined: moved)
    }

    @Test func existingQuarantineNamesGetASuffix() async throws {
        let s = try await makeVault()
        let fm = FileManager.default
        for name in ["20261004-130509", "20261004-130509-2"] {
            let dir = s.vault.quarantineURL.appending(path: name, directoryHint: .isDirectory)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data(name.utf8).write(to: dir.appending(path: "marker"))
        }
        let store = s.vault.makeStore()
        let moved = try await store.quarantineVault(to: s.vault.quarantineURL)
        #expect(moved?.lastPathComponent == "20261004-130509-3")
        try await store.open()
        try await expectFreshVault(s, store, quarantined: moved)
        for name in ["20261004-130509", "20261004-130509-2"] {
            let marker = s.vault.quarantineURL.appending(path: "\(name)/marker")
            #expect(try Data(contentsOf: marker) == Data(name.utf8))
        }
    }

    @Test func folderNameIsUTCNotLocalTime() async throws {
        // 20:30 UTC on 4 Oct is already 5 Oct in Jakarta (UTC+7).
        let s = try await makeVault()
        s.vault.clock.set(Date(timeIntervalSince1970: 1_791_145_800))
        let moved = try await s.vault.makeStore().quarantineVault(to: s.vault.quarantineURL)
        #expect(moved?.lastPathComponent == "20261004-203000")
    }

    @Test func nothingToQuarantineReturnsNil() async throws {
        let vault = try TestVault(clock: TestClock(Self.resetTime))
        let store = vault.makeStore()
        #expect(try await store.quarantineVault(to: vault.quarantineURL) == nil)
        #expect(!FileManager.default.fileExists(atPath: vault.quarantineURL.path))
    }

    @Test func quarantiningAnOpenVaultLocksTheStore() async throws {
        let s = try await makeVault()
        let store = s.vault.makeStore()
        try await store.open()
        let moved = try await store.quarantineVault(to: s.vault.quarantineURL)
        await #expect(throws: VaultError.locked) { try await store.documents() }
        try await store.open()
        try await expectFreshVault(s, store, quarantined: moved)
        await #expect(throws: VaultError.documentNotFound) { try await store.fields(of: s.documentID) }
    }

    // MARK: Listing and deleting ("Data lama")

    struct TwoQuarantines {
        let s: Setup
        let store: VaultStore
        let first: URL
        let second: URL
        let secondID: VaultID
    }

    /// Two quarantined vaults (the first one's key present), and a new live vault.
    func makeTwoQuarantines() async throws -> TwoQuarantines {
        let s = try await makeVault()
        let store = s.vault.makeStore()
        let first = try #require(try await store.quarantineVault(to: s.vault.quarantineURL))
        try await store.open()
        _ = try await store.createDocument(type: .sim, expiry: nil, pinned: false,
                                           fields: Synthetic.simFields, pages: [Synthetic.page("sim")])
        let secondID = try s.vault.header().vaultId
        s.vault.clock.advance(by: 60)
        let second = try #require(try await store.quarantineVault(to: s.vault.quarantineURL))
        try await store.open()
        return TwoQuarantines(s: s, store: store, first: first, second: second, secondID: secondID)
    }

    func size(of folder: URL) throws -> Int64 {
        Int64(try TestVault.files(in: folder).values.reduce(0) { $0 + $1.count })
    }

    @Test func listsQuarantinedVaultsAndReportsUnreadableFolders() async throws {
        let q = try await makeTwoQuarantines()
        let fm = FileManager.default
        let garbled = q.s.vault.quarantineURL.appending(path: "20261004-140000", directoryHint: .isDirectory)
        try fm.createDirectory(at: garbled, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: garbled.appending(path: "vault.json"))
        let empty = q.s.vault.quarantineURL.appending(path: "20261004-150000", directoryHint: .isDirectory)
        try fm.createDirectory(at: empty, withIntermediateDirectories: true)
        try Data("stray".utf8).write(to: q.s.vault.quarantineURL.appending(path: "notes.txt"))
        let before = try TestVault.files(in: q.s.vault.quarantineURL)

        let listing = try await q.store.quarantinedVaults(in: q.s.vault.quarantineURL)
        #expect(listing.vaults.map(\.vaultID) == [q.s.oldHeader.vaultId, q.secondID])
        #expect(listing.vaults.map { $0.folder.standardizedFileURL } == [q.first, q.second].map(\.standardizedFileURL))
        #expect(listing.vaults.map(\.sizeInBytes) == [try size(of: q.first), try size(of: q.second)])
        #expect(listing.unreadableFolders.map { $0.standardizedFileURL } == [garbled, empty].map(\.standardizedFileURL))
        #expect(try TestVault.files(in: q.s.vault.quarantineURL) == before)  // listing touches nothing
    }

    @Test func listingAMissingQuarantineFolderIsEmpty() async throws {
        let vault = try TestVault()
        let listing = try await vault.makeStore().quarantinedVaults(in: vault.quarantineURL)
        #expect(listing == QuarantineListing(vaults: [], unreadableFolders: []))
    }

    @Test func deletesAQuarantinedVaultWithItsKey() async throws {
        let q = try await makeTwoQuarantines()
        let liveFiles = try TestVault.files(in: q.s.vault.root)
        let secondFiles = try TestVault.files(in: q.second)
        let listing = try await q.store.quarantinedVaults(in: q.s.vault.quarantineURL)

        try await q.store.deleteQuarantinedVault(listing.vaults[0])
        #expect(!FileManager.default.fileExists(atPath: q.first.path))
        #expect(await q.s.vault.keyStore.key(for: q.s.oldHeader.vaultId) == nil)
        // The other quarantine, its key and the live vault are untouched.
        #expect(try TestVault.files(in: q.second) == secondFiles)
        #expect(await q.s.vault.keyStore.key(for: q.secondID) != nil)
        #expect(try TestVault.files(in: q.s.vault.root) == liveFiles)
        #expect(try await q.store.quarantinedVaults(in: q.s.vault.quarantineURL).vaults.map(\.vaultID) == [q.secondID])
    }

    @Test func deletingWhenTheKeyIsAlreadyGoneStillRemovesTheFolder() async throws {
        let q = try await makeTwoQuarantines()
        await q.s.vault.keyStore.setKey(nil, for: q.s.oldHeader.vaultId)
        let listing = try await q.store.quarantinedVaults(in: q.s.vault.quarantineURL)
        try await q.store.deleteQuarantinedVault(listing.vaults[0])
        #expect(!FileManager.default.fileExists(atPath: q.first.path))
    }

    @Test func failedKeyDeletionKeepsTheFolder() async throws {
        let q = try await makeTwoQuarantines()
        let files = try TestVault.files(in: q.first)
        let listing = try await q.store.quarantinedVaults(in: q.s.vault.quarantineURL)
        await q.s.vault.keyStore.setDeleteFailure(status: -25308)
        await #expect(throws: VaultError.vaultKeyUnavailable(status: -25308)) {
            try await q.store.deleteQuarantinedVault(listing.vaults[0])
        }
        #expect(try TestVault.files(in: q.first) == files)  // retry is possible from "Data lama"
    }

    @Test func refusesAFolderWhoseVaultFileChanged() async throws {
        let q = try await makeTwoQuarantines()
        let listing = try await q.store.quarantinedVaults(in: q.s.vault.quarantineURL)
        try Data("not json".utf8).write(to: q.first.appending(path: "vault.json"))
        let files = try TestVault.files(in: q.first)
        await #expect(throws: VaultError.quarantineUnreadable) {
            try await q.store.deleteQuarantinedVault(listing.vaults[0])
        }
        #expect(try TestVault.files(in: q.first) == files)
        #expect(await q.s.vault.keyStore.key(for: q.s.oldHeader.vaultId) != nil)
        #expect(await q.s.vault.keyStore.deleteCount == 0)
    }

    @Test func refusesAnEntryThatNamesAnotherVault() async throws {
        let q = try await makeTwoQuarantines()
        let listing = try await q.store.quarantinedVaults(in: q.s.vault.quarantineURL)
        let mismatched = QuarantinedVault(vaultID: q.secondID, folder: listing.vaults[0].folder,
                                          sizeInBytes: listing.vaults[0].sizeInBytes)
        await #expect(throws: VaultError.quarantineUnreadable) { try await q.store.deleteQuarantinedVault(mismatched) }
        #expect(FileManager.default.fileExists(atPath: q.first.path))
        #expect(await q.s.vault.keyStore.deleteCount == 0)
    }

    @Test func refusesTheVaultInUse() async throws {
        // A copy of the live vault inside Quarantine/ must never cost the live vault its key.
        let q = try await makeTwoQuarantines()
        let liveID = try q.s.vault.header().vaultId
        let copy = q.s.vault.quarantineURL.appending(path: "20261004-160000", directoryHint: .isDirectory)
        try FileManager.default.copyItem(at: q.s.vault.root, to: copy)
        let entry = try #require(try await q.store.quarantinedVaults(in: q.s.vault.quarantineURL)
            .vaults.first { $0.vaultID == liveID })

        await #expect(throws: VaultError.quarantineInUse) { try await q.store.deleteQuarantinedVault(entry) }
        #expect(FileManager.default.fileExists(atPath: copy.path))
        #expect(await q.s.vault.keyStore.key(for: liveID) != nil)
        #expect(await q.s.vault.keyStore.deleteCount == 0)
    }
}
