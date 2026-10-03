import Foundation
import Testing
@testable import VaultCore

@Suite("VaultStore lifecycle")
struct VaultStoreTests {
    @Test func newVaultCreatesHeaderIndexAndProjection() async throws {
        let vault = try TestVault()
        let report = try await vault.makeStore().open()
        #expect(report.createdVault)
        let header = try vault.header()
        #expect(header.formatVersion == 1)
        #expect(header.keySlots.map(\.kind) == [.device])
        #expect(FileManager.default.fileExists(atPath: vault.indexURL.path))
        #expect(try vault.projection().documents.isEmpty)
        #expect(await vault.keyStore.createCount == 1)

        // Reopening the same vault uses the existing key.
        let again = try await vault.makeStore().open()
        #expect(!again.createdVault)
        #expect(again.indexSource == .current)
        #expect(await vault.keyStore.createCount == 1)
    }

    @Test func createAndReadDocument() async throws {
        let vault = try TestVault()
        let store = vault.makeStore()
        try await store.open()
        let pages = [Synthetic.page("ktp-front"), Synthetic.page("ktp-back")]
        let id = try await store.createDocument(type: .ktp, expiry: nil, pinned: true,
                                                fields: Synthetic.ktpFields, pages: pages)

        let doc = try await store.document(id)
        #expect(doc.type == .ktp)
        #expect(doc.pinned)
        #expect(doc.deletedAt == nil)
        #expect(doc.pageIDs.count == 2)
        #expect(try await store.fields(of: id) == Synthetic.ktpFields)
        #expect(try await store.pages(of: id).map(\.data) == pages)
        #expect(try await store.page(doc.pageIDs[1], of: id).data == pages[1])

        // Survives a reopen.
        let reopened = vault.makeStore()
        try await reopened.open()
        #expect(try await reopened.snapshot() == store.snapshot())
    }

    @Test func noPlaintextFieldsOrPagesOnDisk() async throws {
        let vault = try TestVault()
        let store = vault.makeStore()
        try await store.open()
        let page = Synthetic.page("ktp-front")
        let id = try await store.createDocument(type: .ktp, expiry: nil, pinned: false,
                                                fields: Synthetic.ktpFields, pages: [page])
        try await store.editDocument(id, type: .ktp, expiry: nil, pinned: false, fields: Synthetic.ktpFields)
        for file in try vault.allFiles() {
            let data = try Data(contentsOf: file)
            #expect(!data.contains(bytes: Data(Synthetic.nik.utf8)), "NIK in \(file.lastPathComponent)")
            #expect(!data.contains(bytes: Data(Synthetic.name.utf8)), "name in \(file.lastPathComponent)")
            #expect(!data.contains(bytes: page.prefix(64)), "page bytes in \(file.lastPathComponent)")
        }
    }

    @Test func editFieldsTypeAndExpiry() async throws {
        let vault = try TestVault()
        let store = vault.makeStore()
        try await store.open()
        let id = try await store.createDocument(type: .other, expiry: nil, pinned: false,
                                                fields: DocumentFields(), pages: [Synthetic.page("sim")])
        let created = try await store.document(id)
        vault.clock.advance(by: 60)

        try await store.editDocument(id, type: .sim, expiry: Synthetic.simExpiry, pinned: true,
                                     fields: Synthetic.simFields)
        let edited = try await store.document(id)
        #expect(edited.type == .sim)
        #expect(edited.expiry == Synthetic.simExpiry)
        #expect(edited.pinned)
        #expect(edited.createdAt == created.createdAt)
        #expect(edited.updatedAt > created.updatedAt)
        #expect(try await store.fields(of: id) == Synthetic.simFields)
        #expect(try vault.projection().documents
            == [ProjectionEntry(id: id, type: .sim, expiry: Synthetic.simExpiry, reminderOffsets: [60, 30, 7])])
    }

    @Test func addAndReplacePages() async throws {
        let vault = try TestVault()
        let store = vault.makeStore()
        try await store.open()
        let id = try await store.createDocument(type: .passport, expiry: nil, pinned: false,
                                                fields: DocumentFields(), pages: [Synthetic.page("p1")])
        let added = try await store.addPage(Synthetic.page("p2"), to: id)
        #expect(try await store.document(id).pageIDs.last == added)

        let first = try await store.document(id).pageIDs[0]
        let replacement = try await store.replacePage(first, of: id, with: Synthetic.page("p1-rescan"))
        let doc = try await store.document(id)
        #expect(doc.pageIDs == [replacement, added])
        #expect(try await store.pages(of: id).map(\.data) == [Synthetic.page("p1-rescan"), Synthetic.page("p2")])
        // The old page file is deleted after the index points away from it.
        #expect(!FileManager.default.fileExists(atPath: vault.pageURL(first).path))
        #expect(try vault.pageFiles().count == 2)
    }

    @Test func softDeleteAndRestore() async throws {
        let vault = try TestVault()
        let store = vault.makeStore()
        try await store.open()
        let id = try await store.createDocument(type: .sim, expiry: Synthetic.simExpiry, pinned: false,
                                                fields: Synthetic.simFields, pages: [Synthetic.page("sim")])
        #expect(try vault.projection().documents.map(\.id) == [id])

        try await store.delete(id)
        #expect(try await store.documents().isEmpty)
        #expect(try await store.recentlyDeleted().map(\.id) == [id])
        #expect(try await store.document(id).deletedAt != nil)
        #expect(try vault.projection().documents.isEmpty)
        // Keys and files stay while in Recently deleted.
        #expect(try await store.pages(of: id).count == 1)
        #expect(try await store.fields(of: id) == Synthetic.simFields)

        try await store.restore(id)
        #expect(try await store.documents().map(\.id) == [id])
        #expect(try await store.recentlyDeleted().isEmpty)
        #expect(try vault.projection().documents.map(\.id) == [id])
    }

    @Test func projectionUsesInjectedReminderOffsets() async throws {
        let vault = try TestVault()
        let store = VaultStore(rootDirectory: vault.root, projectionURL: vault.projectionURL,
                               keyStore: vault.keyStore, clock: vault.clock, reminderOffsets: [90, 14])
        try await store.open()
        _ = try await store.createDocument(type: .stnk, expiry: Synthetic.simExpiry, pinned: false,
                                           fields: DocumentFields(), pages: [])
        #expect(try vault.projection().documents.map(\.reminderOffsets) == [[90, 14]])
    }

    @Test func lockedStoreRefusesAccess() async throws {
        let vault = try TestVault()
        let store = vault.makeStore()
        await #expect(throws: VaultError.locked) { try await store.documents() }
        try await store.open()
        let id = try await store.createDocument(type: .ktp, expiry: nil, pinned: false,
                                                fields: Synthetic.ktpFields, pages: [Synthetic.page("k")])
        await store.lock()
        await #expect(throws: VaultError.locked) { try await store.fields(of: id) }
        await #expect(throws: VaultError.locked) { try await store.pages(of: id) }
        try await store.open()
        #expect(try await store.fields(of: id) == Synthetic.ktpFields)
    }

    @Test func unknownIdsAreReported() async throws {
        let vault = try TestVault()
        let store = vault.makeStore()
        try await store.open()
        await #expect(throws: VaultError.documentNotFound) { try await store.fields(of: DocumentID()) }
        let id = try await store.createDocument(type: .ktp, expiry: nil, pinned: false,
                                                fields: Synthetic.ktpFields, pages: [Synthetic.page("k")])
        await #expect(throws: VaultError.pageNotFound) { try await store.page(PageID(), of: id) }
    }

    @Test func timestampsAreWholeSeconds() async throws {
        let vault = try TestVault(clock: TestClock(Date(timeIntervalSince1970: 1_790_000_000.75)))
        let store = vault.makeStore()
        try await store.open()
        let id = try await store.createDocument(type: .ktp, expiry: nil, pinned: false,
                                                fields: Synthetic.ktpFields, pages: [])
        #expect(try await store.document(id).createdAt == Date(timeIntervalSince1970: 1_790_000_000))
    }
}
