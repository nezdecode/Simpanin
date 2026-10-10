import Foundation
import Testing

@testable import VaultCore

/// Tampered, swapped or stale files fail to open.
@Suite("Tampering")
struct TamperTests {
    func makeVaultWithTwoDocuments() async throws -> (TestVault, VaultStore, DocumentID, DocumentID) {
        let vault = try TestVault()
        let store = vault.makeStore()
        try await store.open()
        let ktp = try await store.createDocument(
            type: .ktp, expiry: nil, pinned: false,
            fields: Synthetic.ktpFields, pages: [Synthetic.page("a")])
        let sim = try await store.createDocument(
            type: .sim, expiry: Synthetic.simExpiry, pinned: false,
            fields: Synthetic.simFields, pages: [Synthetic.page("b")])
        return (vault, store, ktp, sim)
    }

    func flipByte(in url: URL, at offset: (Data) -> Int) throws {
        var data = try Data(contentsOf: url)
        data[offset(data)] ^= 0x01
        try data.write(to: url)
    }

    // MARK: Test 1, store level: one flipped byte fails to open

    @Test func flippedByteInPageContentFailsToOpen() async throws {
        let (vault, store, ktp, _) = try await makeVaultWithTwoDocuments()
        let pageID = try await store.document(ktp).pageIDs[0]
        try flipByte(in: vault.pageURL(pageID)) { $0.count - 20 }  // inside the sealed content
        await #expect(throws: VaultError.authenticationFailed) { try await store.page(pageID, of: ktp) }
    }

    @Test func flippedByteInPageHeaderFailsToOpen() async throws {
        let (vault, store, ktp, _) = try await makeVaultWithTwoDocuments()
        let pageID = try await store.document(ktp).pageIDs[0]
        let url = vault.pageURL(pageID)
        let original = try Data(contentsOf: url)
        // Change one character of the docId inside the plaintext header.
        let docText = Data(ktp.string.utf8)
        let index = try #require(original.range(of: docText)).lowerBound + 2
        var data = original
        data[index] = data[index] == UInt8(ascii: "0") ? UInt8(ascii: "1") : UInt8(ascii: "0")
        try data.write(to: url)
        await #expect(throws: VaultError.self) { try await store.page(pageID, of: ktp) }
    }

    @Test func flippedByteInIndexFallsBackToPreviousIndex() async throws {
        let (vault, _, ktp, sim) = try await makeVaultWithTwoDocuments()
        try flipByte(in: vault.indexURL) { $0.count / 2 }

        let reopened = vault.makeStore()
        let report = try await reopened.open()
        #expect(report.indexSource == .previous)
        #expect(report.newestChangeMayBeLost)
        #expect(!report.recoveredFromPages)
        // index.prev.enc is one generation older and lacks the SIM. Its page was committed, so
        // it is re-attached from the page header; only its fields are lost.
        #expect(try await reopened.documents().map(\.id) == [ktp, sim])
        #expect(try await reopened.fields(of: ktp) == Synthetic.ktpFields)
        #expect(try await reopened.document(sim).type == .other)
        #expect(try await reopened.fields(of: sim) == DocumentFields())
        #expect(try await reopened.pages(of: sim).map(\.data) == [Synthetic.page("b")])
        // The unreadable index.enc is replaced by a good one on open.
        #expect(try await vault.makeStore().open().indexSource == .current)
    }

    // MARK: Test 2: a page copied into another document's slot fails to open

    @Test func pageCopiedIntoAnotherDocumentsSlotFailsToOpen() async throws {
        let (vault, store, ktp, sim) = try await makeVaultWithTwoDocuments()
        let ktpPage = try await store.document(ktp).pageIDs[0]
        let simPage = try await store.document(sim).pageIDs[0]
        try FileManager.default.removeItem(at: vault.pageURL(simPage))
        try FileManager.default.copyItem(at: vault.pageURL(ktpPage), to: vault.pageURL(simPage))
        await #expect(throws: VaultError.authenticationFailed) { try await store.page(simPage, of: sim) }
        // The KTP's own page still opens.
        #expect(try await store.page(ktpPage, of: ktp).data == Synthetic.page("a"))
    }

    @Test func pageWithRewrittenHeaderStillFailsToOpenInAnotherSlot() async throws {
        // Even with the header claiming the SIM, the KTP's page is sealed with the KTP's key
        // and associated data, so it cannot open as the SIM's.
        let (vault, store, ktp, sim) = try await makeVaultWithTwoDocuments()
        let ktpPage = try await store.document(ktp).pageIDs[0]
        let simPage = try await store.document(sim).pageIDs[0]
        let ktpFile = try PageFile(decoding: Data(contentsOf: vault.pageURL(ktpPage)))
        let simFile = try PageFile(decoding: Data(contentsOf: vault.pageURL(simPage)))
        let forged = PageFile(header: simFile.header, sealedContent: ktpFile.sealedContent)
        try forged.encoded().write(to: vault.pageURL(simPage))
        await #expect(throws: VaultError.authenticationFailed) { try await store.page(simPage, of: sim) }
    }

    @Test func pageSwappedWithinTheSameDocumentFailsToOpen() async throws {
        // Same document, same key, same sealed key in the header: only the page id in the
        // associated data ("page|v1|<docId>|<pageId>") can tell page 1 from page 2.
        let vault = try TestVault()
        let store = vault.makeStore()
        try await store.open()
        let id = try await store.createDocument(
            type: .ktp, expiry: nil, pinned: false, fields: Synthetic.ktpFields,
            pages: [Synthetic.page("front"), Synthetic.page("back")])
        let pages = try await store.document(id).pageIDs
        let first = try PageFile(decoding: Data(contentsOf: vault.pageURL(pages[0])))
        let second = try PageFile(decoding: Data(contentsOf: vault.pageURL(pages[1])))
        try PageFile(header: second.header, sealedContent: first.sealedContent).encoded()
            .write(to: vault.pageURL(pages[1]))
        await #expect(throws: VaultError.authenticationFailed) { try await store.page(pages[1], of: id) }
        #expect(try await store.page(pages[0], of: id).data == Synthetic.page("front"))
    }

    // MARK: Test 2: an older index put back fails to open

    @Test func olderIndexPutBackIsRejected() async throws {
        let (vault, store, ktp, sim) = try await makeVaultWithTwoDocuments()
        let stale = try Data(contentsOf: vault.indexURL)  // generation with both documents
        try await store.delete(ktp)  // newer generations
        try await store.editDocument(sim, type: .sim, expiry: nil, pinned: true, fields: Synthetic.simFields)
        let previous = try await vault.readIndex(at: vault.previousIndexURL)

        try stale.write(to: vault.indexURL)  // put the old index back
        let reopened = vault.makeStore()
        let report = try await reopened.open()
        #expect(report.indexSource == .previous)
        #expect(report.newestChangeMayBeLost)
        // The stale copy is not used: the vault shows index.prev.enc's newer generation.
        #expect(try await reopened.recentlyDeleted().map(\.id) == [ktp])
        #expect(try await vault.readIndex(at: vault.indexURL).generation > previous.generation)
    }

    @Test func indexFromAnotherVaultFailsToOpen() async throws {
        let (vault, _, _, _) = try await makeVaultWithTwoDocuments()
        let (other, _, _, _) = try await makeVaultWithTwoDocuments()
        try FileManager.default.removeItem(at: vault.indexURL)
        try FileManager.default.copyItem(at: other.indexURL, to: vault.indexURL)
        let report = try await vault.makeStore().open()
        #expect(report.indexSource == .previous)
        #expect(report.newestChangeMayBeLost)
    }
}
