import Crypto
import Foundation
import Testing
@testable import VaultCore

/// Design doc, write order step 2: "If step 3 will delete any file, first flush the new index
/// to disk with F_FULLFSYNC, so a power loss cannot leave a deleted page that the surviving
/// index still needs."
@Suite("Index flush before deleting pages")
struct FlushTests {
    struct FlushError: Error {}

    func makeStore(_ vault: TestVault, _ flusher: RecordingFlusher) async throws -> VaultStore {
        let store = vault.makeStore(flusher: flusher)
        try await store.open()
        return store
    }

    func generation(of sealedIndex: Data, in vault: TestVault) async throws -> VaultIndex {
        let header = try vault.header()
        let key = try #require(await vault.keyStore.key(for: header.vaultId))
        let plain = try VaultCrypto.open(sealedIndex, with: VaultCrypto.indexKey(from: key, vaultID: header.vaultId),
                                         as: .index(header.vaultId))
        return try VaultJSON.decoder.decode(VaultIndex.self, from: plain)
    }

    @Test func noFlushWhenNothingIsDeleted() async throws {
        let vault = try TestVault()
        let flusher = RecordingFlusher(pagesDirectory: vault.pagesDirectory)
        let store = try await makeStore(vault, flusher)
        let id = try await store.createDocument(type: .ktp, expiry: nil, pinned: false,
                                                fields: Synthetic.ktpFields, pages: [Synthetic.page("k")])
        try await store.editDocument(id, type: .ktp, expiry: nil, pinned: true, fields: Synthetic.ktpFields)
        _ = try await store.addPage(Synthetic.page("k2"), to: id)
        try await store.delete(id)
        try await store.restore(id)
        #expect(flusher.recorded.isEmpty)
        #expect(await store.lastFlushMethod == nil)
    }

    @Test func replacePageFlushesTheNewIndexBeforeDeletingTheOldPage() async throws {
        let vault = try TestVault()
        let flusher = RecordingFlusher(pagesDirectory: vault.pagesDirectory)
        let store = try await makeStore(vault, flusher)
        let id = try await store.createDocument(type: .ktp, expiry: nil, pinned: false, fields: Synthetic.ktpFields,
                                                pages: [Synthetic.page("front"), Synthetic.page("back")])
        let generationBefore = try await vault.readIndex(at: vault.indexURL).generation
        let old = try await store.document(id).pageIDs[0]
        let new = try await store.replacePage(old, of: id, with: Synthetic.page("front-rescan"))

        let events = flusher.recorded
        try #require(events.count == 1)
        #expect(events[0].url.standardizedFileURL == vault.indexURL.standardizedFileURL)
        // At flush time the new index was already written...
        let flushed = try await generation(of: events[0].contents, in: vault)
        #expect(flushed.generation == generationBefore + 1)
        #expect(flushed.documents.first?.pageIds.first == new)
        // ...and the old page had not been deleted yet.
        #expect(events[0].pageFiles.contains("\(old.string).enc"))
        #expect(!FileManager.default.fileExists(atPath: vault.pageURL(old).path))
        #expect(await store.lastFlushMethod == .fullFsync)
    }

    @Test func purgeFlushesOnceAfterBothIndexWrites() async throws {
        let vault = try TestVault()
        let flusher = RecordingFlusher(pagesDirectory: vault.pagesDirectory)
        let store = try await makeStore(vault, flusher)
        let id = try await store.createDocument(type: .ktp, expiry: nil, pinned: false, fields: Synthetic.ktpFields,
                                                pages: [Synthetic.page("p1"), Synthetic.page("p2")])
        let pages = try await store.document(id).pageIDs
        let generationBefore = try await vault.readIndex(at: vault.indexURL).generation
        try await store.deletePermanently(id)

        let events = flusher.recorded
        try #require(events.count == 1)
        let flushed = try await generation(of: events[0].contents, in: vault)
        #expect(flushed.generation == generationBefore + 2)
        #expect(flushed.documents.isEmpty)
        for page in pages { #expect(events[0].pageFiles.contains("\(page.string).enc")) }
    }

    @Test func purgeOfADocumentWithoutPagesDoesNotFlush() async throws {
        let vault = try TestVault()
        let flusher = RecordingFlusher(pagesDirectory: vault.pagesDirectory)
        let store = try await makeStore(vault, flusher)
        let id = try await store.createDocument(type: .npwp, expiry: nil, pinned: false,
                                                fields: DocumentFields(["number": "00.000.000.0-000.000"]), pages: [])
        try await store.deletePermanently(id)
        #expect(flusher.recorded.isEmpty)
    }

    @Test func obsoletePageAlreadyGoneDoesNotFlush() async throws {
        let vault = try TestVault()
        let flusher = RecordingFlusher(pagesDirectory: vault.pagesDirectory)
        let store = try await makeStore(vault, flusher)
        let id = try await store.createDocument(type: .ktp, expiry: nil, pinned: false, fields: Synthetic.ktpFields,
                                                pages: [Synthetic.page("front")])
        let old = try await store.document(id).pageIDs[0]
        try FileManager.default.removeItem(at: vault.pageURL(old))
        _ = try await store.replacePage(old, of: id, with: Synthetic.page("front-rescan"))
        #expect(flusher.recorded.isEmpty)
    }

    @Test func failedFlushDeletesNothing() async throws {
        let vault = try TestVault()
        let flusher = RecordingFlusher(pagesDirectory: vault.pagesDirectory, failure: FlushError())
        let store = try await makeStore(vault, flusher)
        let id = try await store.createDocument(type: .ktp, expiry: nil, pinned: false, fields: Synthetic.ktpFields,
                                                pages: [Synthetic.page("front")])
        let old = try await store.document(id).pageIDs[0]
        await #expect(throws: VaultError.flushFailed) {
            try await store.replacePage(old, of: id, with: Synthetic.page("front-rescan"))
        }
        #expect(FileManager.default.fileExists(atPath: vault.pageURL(old).path))

        // The new index was written; the next open uses it and cleans up the old page later.
        vault.clock.advance(by: 3600)
        let reopened = vault.makeStore()
        try await reopened.open()
        #expect(try await reopened.pages(of: id).map(\.data) == [Synthetic.page("front-rescan")])
        #expect(!FileManager.default.fileExists(atPath: vault.pageURL(old).path))
    }

    @Test func recordsTheMethodThatRan() async throws {
        let vault = try TestVault()
        let flusher = RecordingFlusher(pagesDirectory: vault.pagesDirectory, method: .fsync)
        let store = try await makeStore(vault, flusher)
        let id = try await store.createDocument(type: .ktp, expiry: nil, pinned: false, fields: Synthetic.ktpFields,
                                                pages: [Synthetic.page("front")])
        _ = try await store.replacePage(try await store.document(id).pageIDs[0], of: id, with: Synthetic.page("x"))
        #expect(await store.lastFlushMethod == .fsync)
    }

    // MARK: The real flusher

    func tempFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "flush-\(UUID().uuidString).bin")
        try Data("synthetic".utf8).write(to: url)
        return url
    }

    @Test func fallsBackToFsyncWhenFullFsyncIsRejected() throws {
        let url = try tempFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let flusher = FileSystemFlusher(fullSync: { _ in -1 })
        #expect(try flusher.flush(url) == .fsync)
    }

    @Test func missingFileFailsToFlush() {
        let url = FileManager.default.temporaryDirectory.appending(path: "missing-\(UUID().uuidString).bin")
        #expect(throws: VaultError.flushFailed) { try FileSystemFlusher().flush(url) }
    }

    @Test func realFlushOnThisMachine() throws {
        let url = try tempFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let method = try FileSystemFlusher().flush(url)
        print("FLUSH METHOD ON THIS MACHINE: \(method)")
        #if canImport(Darwin)
        #expect(method == .fullFsync)
        #else
        #expect(method == .fsync)
        #endif
    }
}
