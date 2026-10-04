import Crypto
import Foundation
import Testing
@testable import VaultCore

/// Required test 5: after a purge, no file in the vault holds the purged sealed key.
@Suite("Purge")
struct PurgeTests {
    struct Setup {
        let vault: TestVault
        let store: VaultStore
        let purged: DocumentID
        let kept: DocumentID
        let purgedPages: [PageID]
        let sealedKey: Data
        let rawKey: Data
        let deletedAt: Date
    }

    func makeSetup() async throws -> Setup {
        let vault = try TestVault(clock: TestClock(Date(timeIntervalSince1970: 1_790_000_000)))
        let store = vault.makeStore()
        try await store.open()
        let purged = try await store.createDocument(type: .ktp, expiry: nil, pinned: false, fields: Synthetic.ktpFields,
                                                    pages: [Synthetic.page("p1"), Synthetic.page("p2")])
        let kept = try await store.createDocument(type: .sim, expiry: Synthetic.simExpiry, pinned: false,
                                                  fields: Synthetic.simFields, pages: [Synthetic.page("k1")])
        try await store.editDocument(purged, type: .ktp, expiry: nil, pinned: true, fields: Synthetic.ktpFields)
        try await store.delete(purged)

        let entry = try #require(try await vault.readIndex(at: vault.indexURL).documents.first { $0.id == purged })
        let header = try vault.header()
        let vaultKey = try #require(await vault.keyStore.key(for: header.vaultId))
        let wrapKey = VaultCrypto.wrapKey(from: vaultKey, vaultID: header.vaultId)
        let rawKey = bytes(try VaultCrypto.openDocumentKey(entry.sealedKey, with: wrapKey, documentID: purged))
        return Setup(vault: vault, store: store, purged: purged, kept: kept, purgedPages: entry.pageIds,
                     sealedKey: entry.sealedKey, rawKey: rawKey, deletedAt: try #require(entry.deletedAt))
    }

    func expectNoTrace(_ s: Setup, _ store: VaultStore) async throws {
        #expect(try await store.documents().map(\.id) == [s.kept])
        #expect(try await store.recentlyDeleted().isEmpty)
        await #expect(throws: VaultError.documentNotFound) { try await store.fields(of: s.purged) }
        for page in s.purgedPages {
            #expect(!FileManager.default.fileExists(atPath: s.vault.pageURL(page).path))
        }
        // Both index files open and neither holds the entry or its sealed key.
        for url in [s.vault.indexURL, s.vault.previousIndexURL] {
            let index = try await s.vault.readIndex(at: url)
            #expect(!index.documents.contains { $0.id == s.purged }, "\(url.lastPathComponent)")
            #expect(!index.documents.contains { $0.sealedKey == s.sealedKey }, "\(url.lastPathComponent)")
        }
        // No remaining page header holds the sealed key. Headers are decoded, not byte-scanned:
        // the key is base64 inside JSON there, which escapes "/", so a byte search cannot find it.
        for file in try s.vault.pageFiles() {
            let header = try PageFile(decoding: Data(contentsOf: file)).header
            #expect(header.sealedKey != s.sealedKey, "sealed key in \(file.lastPathComponent)")
            #expect(header.docId != s.purged, "page of the purged document: \(file.lastPathComponent)")
        }
        // The document id appears as plain text in page headers, so a byte scan does work for it.
        for file in try s.vault.allFiles() {
            let data = try Data(contentsOf: file)
            #expect(!data.contains(bytes: Data(s.purged.string.utf8)), "doc id in \(file.lastPathComponent)")
        }
        // The other document is untouched.
        #expect(try await store.fields(of: s.kept) == Synthetic.simFields)
        #expect(try await store.pages(of: s.kept).map(\.data) == [Synthetic.page("k1")])
    }

    @Test func notPurgedBeforeThirtyDays() async throws {
        let s = try await makeSetup()
        s.vault.clock.set(s.deletedAt + 30 * 86_400 - 1)
        let store = s.vault.makeStore()
        #expect(try await store.open().purgedDocuments == 0)
        #expect(try await store.recentlyDeleted().map(\.id) == [s.purged])
        #expect(try await store.fields(of: s.purged) == Synthetic.ktpFields)
    }

    @Test func purgedOnUnlockAfterThirtyDays() async throws {
        let s = try await makeSetup()
        s.vault.clock.set(s.deletedAt + 30 * 86_400)
        let store = s.vault.makeStore()
        #expect(try await store.open().purgedDocuments == 1)
        try await expectNoTrace(s, store)
    }

    @Test func purgeExpiredWhileOpen() async throws {
        let s = try await makeSetup()
        s.vault.clock.set(s.deletedAt + 31 * 86_400)
        #expect(try await s.store.purgeExpired() == 1)
        try await expectNoTrace(s, s.store)
        #expect(try await s.store.purgeExpired() == 0)
    }

    @Test func deletePermanentlyNow() async throws {
        let s = try await makeSetup()
        try await s.store.deletePermanently(s.purged)
        try await expectNoTrace(s, s.store)
    }

    @Test func purgedDocumentDoesNotComeBackThroughRecovery() async throws {
        let s = try await makeSetup()
        try await s.store.deletePermanently(s.purged)
        try Data("x".utf8).write(to: s.vault.indexURL)
        try Data("x".utf8).write(to: s.vault.previousIndexURL)

        let store = s.vault.makeStore()
        #expect(try await store.open().indexSource == .recovered)
        #expect(try await store.documents().map(\.id) == [s.kept])
        #expect(try await store.recentlyDeleted().isEmpty)
        #expect(try await store.pages(of: s.kept).map(\.data) == [Synthetic.page("k1")])
    }

    @Test func purgeWritesTheIndexTwice() async throws {
        let s = try await makeSetup()
        let before = try await s.vault.readIndex(at: s.vault.indexURL).generation
        try await s.store.deletePermanently(s.purged)
        #expect(try await s.vault.readIndex(at: s.vault.indexURL).generation == before + 2)
        #expect(try await s.vault.readIndex(at: s.vault.previousIndexURL).generation == before + 1)
    }
}
