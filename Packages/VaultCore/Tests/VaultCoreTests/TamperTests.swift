import Foundation
import Testing
@testable import VaultCore

/// Required tests 1 and 2: tampered, swapped or stale files fail to open.
@Suite("Tampering")
struct TamperTests {
    func makeVaultWithTwoDocuments() async throws -> (TestVault, VaultStore, DocumentID, DocumentID) {
        let vault = try TestVault()
        let store = vault.makeStore()
        try await store.open()
        let a = try await store.createDocument(type: .ktp, expiry: nil, pinned: false,
                                               fields: Synthetic.ktpFields, pages: [Synthetic.page("a")])
        let b = try await store.createDocument(type: .sim, expiry: Synthetic.simExpiry, pinned: false,
                                               fields: Synthetic.simFields, pages: [Synthetic.page("b")])
        return (vault, store, a, b)
    }

    func flipByte(in url: URL, at offset: (Data) -> Int) throws {
        var data = try Data(contentsOf: url)
        data[offset(data)] ^= 0x01
        try data.write(to: url)
    }

    // MARK: Test 1, store level: one flipped byte fails to open

    @Test func flippedByteInPageContentFailsToOpen() async throws {
        let (vault, store, a, _) = try await makeVaultWithTwoDocuments()
        let pageID = try await store.document(a).pageIDs[0]
        try flipByte(in: vault.pageURL(pageID)) { $0.count - 20 }  // inside the sealed content
        await #expect(throws: VaultError.authenticationFailed) { try await store.page(pageID, of: a) }
    }

    @Test func flippedByteInPageHeaderFailsToOpen() async throws {
        let (vault, store, a, _) = try await makeVaultWithTwoDocuments()
        let pageID = try await store.document(a).pageIDs[0]
        let url = vault.pageURL(pageID)
        let original = try Data(contentsOf: url)
        // Change one character of the docId inside the plaintext header.
        let docText = Data(a.string.utf8)
        let at = try #require(original.range(of: docText)).lowerBound + 2
        var data = original
        data[at] = data[at] == UInt8(ascii: "0") ? UInt8(ascii: "1") : UInt8(ascii: "0")
        try data.write(to: url)
        await #expect(throws: VaultError.self) { try await store.page(pageID, of: a) }
    }

    @Test func flippedByteInIndexFallsBackToPreviousIndex() async throws {
        let (vault, _, a, b) = try await makeVaultWithTwoDocuments()
        try flipByte(in: vault.indexURL) { $0.count / 2 }

        let reopened = vault.makeStore()
        let report = try await reopened.open()
        #expect(report.indexSource == .previous)
        // index.prev.enc is one generation older: it has A but not B. B's page was
        // committed, so it is re-attached from its page header instead of deleted;
        // only B's fields (which lived in the lost index) are gone.
        #expect(try await reopened.documents().map(\.id) == [a, b])
        #expect(try await reopened.fields(of: a) == Synthetic.ktpFields)
        #expect(try await reopened.document(b).type == .other)
        #expect(try await reopened.fields(of: b) == DocumentFields())
        #expect(try await reopened.pages(of: b).map(\.data) == [Synthetic.page("b")])
        // The unreadable index.enc is replaced by a good one on open.
        #expect(try await vault.makeStore().open().indexSource == .current)
    }

    // MARK: Test 2: a page copied into another document's slot fails to open

    @Test func pageCopiedIntoAnotherDocumentsSlotFailsToOpen() async throws {
        let (vault, store, a, b) = try await makeVaultWithTwoDocuments()
        let pageA = try await store.document(a).pageIDs[0]
        let pageB = try await store.document(b).pageIDs[0]
        try FileManager.default.removeItem(at: vault.pageURL(pageB))
        try FileManager.default.copyItem(at: vault.pageURL(pageA), to: vault.pageURL(pageB))
        await #expect(throws: VaultError.authenticationFailed) { try await store.page(pageB, of: b) }
        // A's own page still opens.
        #expect(try await store.page(pageA, of: a).data == Synthetic.page("a"))
    }

    @Test func pageWithRewrittenHeaderStillFailsToOpenInAnotherSlot() async throws {
        // Even with the header edited to claim document B, A's content is sealed with A's
        // key and A's associated data, so it cannot open as B's page.
        let (vault, store, a, b) = try await makeVaultWithTwoDocuments()
        let pageA = try await store.document(a).pageIDs[0]
        let pageB = try await store.document(b).pageIDs[0]
        let fileA = try PageFile(decoding: Data(contentsOf: vault.pageURL(pageA)))
        let fileB = try PageFile(decoding: Data(contentsOf: vault.pageURL(pageB)))
        let forged = PageFile(header: fileB.header, sealedContent: fileA.sealedContent)
        try forged.encoded().write(to: vault.pageURL(pageB))
        await #expect(throws: VaultError.authenticationFailed) { try await store.page(pageB, of: b) }
    }

    // MARK: Test 2: an older index put back fails to open

    @Test func olderIndexPutBackIsRejected() async throws {
        let (vault, store, a, b) = try await makeVaultWithTwoDocuments()
        let stale = try Data(contentsOf: vault.indexURL)          // generation with A and B
        try await store.delete(a)                                  // newer generations
        try await store.editDocument(b, type: .sim, expiry: nil, pinned: true, fields: Synthetic.simFields)
        let previous = try await vault.readIndex(at: vault.previousIndexURL)

        try stale.write(to: vault.indexURL)                        // put the old index back
        let reopened = vault.makeStore()
        let report = try await reopened.open()
        #expect(report.indexSource == .previous)
        // The stale copy is not used: the vault shows index.prev.enc's newer generation.
        #expect(try await reopened.recentlyDeleted().map(\.id) == [a])
        #expect(try await vault.readIndex(at: vault.indexURL).generation > previous.generation)
    }

    @Test func indexFromAnotherVaultFailsToOpen() async throws {
        let (vault, _, _, _) = try await makeVaultWithTwoDocuments()
        let (other, _, _, _) = try await makeVaultWithTwoDocuments()
        try FileManager.default.removeItem(at: vault.indexURL)
        try FileManager.default.copyItem(at: other.indexURL, to: vault.indexURL)
        let report = try await vault.makeStore().open()
        #expect(report.indexSource == .previous)
    }
}
