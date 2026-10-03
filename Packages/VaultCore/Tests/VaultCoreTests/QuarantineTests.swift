import Crypto
import Foundation
import Testing
@testable import VaultCore

/// "Mulai vault baru" (design doc, "Recovery screens and quarantine"): the whole vault
/// folder moves to Quarantine/<yyyyMMdd-HHmmss in UTC>/, unchanged, then a new vault with
/// a new vault id is created. Nothing is deleted and the old Keychain item is untouched.
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

    /// The new vault is empty, has a new id and its own key; the old files are intact.
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

    @Test func startNewVaultAfterMissingKey() async throws {
        let s = try await makeVault()
        await s.vault.keyStore.setKey(nil, for: s.oldHeader.vaultId)
        let store = s.vault.makeStore()
        await #expect(throws: VaultError.vaultKeyMissing) { try await store.open() }

        let moved = try await store.startNewVault(quarantineDirectory: s.vault.quarantineURL)
        #expect(moved?.lastPathComponent == "20261004-130509")
        #expect(moved?.deletingLastPathComponent().standardizedFileURL == s.vault.quarantineURL.standardizedFileURL)
        try await expectFreshVault(s, store, quarantined: moved)
        #expect(await s.vault.keyStore.createCount == 2)
    }

    @Test func startNewVaultAfterUnreadableVaultKeepsOldKeyAndFiles() async throws {
        let s = try await makeVault()
        let wrongKey = VaultCrypto.newKey()
        await s.vault.keyStore.setKey(wrongKey, for: s.oldHeader.vaultId)
        let store = s.vault.makeStore()
        await #expect(throws: VaultError.vaultUnreadable) { try await store.open() }

        let moved = try #require(try await store.startNewVault(quarantineDirectory: s.vault.quarantineURL))
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

    @Test func existingQuarantineNamesGetASuffix() async throws {
        let s = try await makeVault()
        let fm = FileManager.default
        for name in ["20261004-130509", "20261004-130509-2"] {
            let dir = s.vault.quarantineURL.appending(path: name, directoryHint: .isDirectory)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data(name.utf8).write(to: dir.appending(path: "marker"))
        }
        let store = s.vault.makeStore()
        let moved = try await store.startNewVault(quarantineDirectory: s.vault.quarantineURL)
        #expect(moved?.lastPathComponent == "20261004-130509-3")
        try await expectFreshVault(s, store, quarantined: moved)
        // Earlier quarantine folders are never touched.
        for name in ["20261004-130509", "20261004-130509-2"] {
            let marker = s.vault.quarantineURL.appending(path: "\(name)/marker")
            #expect(try Data(contentsOf: marker) == Data(name.utf8))
        }
    }

    @Test func folderNameIsUTCNotLocalTime() async throws {
        // 20:30 UTC on 4 Oct is already 5 Oct in Jakarta (UTC+7).
        let s = try await makeVault()
        s.vault.clock.set(Date(timeIntervalSince1970: 1_791_145_800))
        let moved = try await s.vault.makeStore().startNewVault(quarantineDirectory: s.vault.quarantineURL)
        #expect(moved?.lastPathComponent == "20261004-203000")
    }

    @Test func startNewVaultWithNoVaultJustCreatesOne() async throws {
        let vault = try TestVault(clock: TestClock(Self.resetTime))
        let store = vault.makeStore()
        #expect(try await store.startNewVault(quarantineDirectory: vault.quarantineURL) == nil)
        #expect(FileManager.default.fileExists(atPath: vault.headerURL.path))
        #expect(!FileManager.default.fileExists(atPath: vault.quarantineURL.path))
        #expect(try await store.documents().isEmpty)
    }

    @Test func startNewVaultOnAnOpenStoreDropsTheOldState() async throws {
        let s = try await makeVault()
        let store = s.vault.makeStore()
        try await store.open()
        #expect(try await store.documents().count == 1)
        let moved = try await store.startNewVault(quarantineDirectory: s.vault.quarantineURL)
        try await expectFreshVault(s, store, quarantined: moved)
        await #expect(throws: VaultError.documentNotFound) { try await store.fields(of: s.documentID) }
    }
}
