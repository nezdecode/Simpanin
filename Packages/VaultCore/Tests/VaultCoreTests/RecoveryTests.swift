import Crypto
import Foundation
import Testing
@testable import VaultCore

/// Required test 4 (both index files corrupt: every page image is recovered), plus the
/// guards that keep recovery and cleanup from destroying data.
@Suite("Recovery and cleanup")
struct RecoveryTests {
    struct Fixture {
        let vault: TestVault
        let pagesByDocument: [DocumentID: Set<Data>]
    }

    func makeVault() async throws -> Fixture {
        let vault = try TestVault()
        let store = vault.makeStore()
        try await store.open()
        let ktpPages = [Synthetic.page("ktp-front"), Synthetic.page("ktp-back")]
        let a = try await store.createDocument(type: .ktp, expiry: nil, pinned: false,
                                               fields: Synthetic.ktpFields, pages: ktpPages)
        let b = try await store.createDocument(type: .sim, expiry: Synthetic.simExpiry, pinned: false,
                                               fields: Synthetic.simFields, pages: [Synthetic.page("sim")])
        _ = try await store.replacePage(try await store.document(b).pageIDs[0], of: b,
                                        with: Synthetic.page("sim-rescan"))
        try await store.delete(b)
        return Fixture(vault: vault, pagesByDocument: [a: Set(ktpPages), b: [Synthetic.page("sim-rescan")]])
    }

    func recoveredPages(_ store: VaultStore) async throws -> [DocumentID: Set<Data>] {
        var result: [DocumentID: Set<Data>] = [:]
        for doc in try await store.documents() + store.recentlyDeleted() {
            result[doc.id] = Set(try await store.pages(of: doc.id).map(\.data))
        }
        return result
    }

    @Test func bothIndexFilesCorruptRecoversEveryPage() async throws {
        let f = try await makeVault()
        try Data("not an index".utf8).write(to: f.vault.indexURL)
        try Data(repeating: 0, count: 300).write(to: f.vault.previousIndexURL)

        let store = f.vault.makeStore()
        let report = try await store.open()
        #expect(report.indexSource == .recovered)
        #expect(report.recoveredFromPages)
        #expect(!report.newestChangeMayBeLost)
        #expect(report.unreadablePages == 0)
        #expect(try await recoveredPages(store) == f.pagesByDocument)
        // Fields lived only in the index, so they are gone; the documents are not.
        for doc in try await store.documents() {
            #expect(doc.type == .other)
            #expect(try await store.fields(of: doc.id) == DocumentFields())
        }
        // Recovered documents come back as live, and the rebuilt index opens normally next time.
        #expect(try await store.recentlyDeleted().isEmpty)
        let again = f.vault.makeStore()
        let againReport = try await again.open()
        #expect(againReport.indexSource == .current)
        #expect(!againReport.recoveredFromPages)  // a one-time notice
        #expect(try await recoveredPages(again) == f.pagesByDocument)
    }

    @Test func bothIndexFilesMissingRecoversEveryPage() async throws {
        let f = try await makeVault()
        try FileManager.default.removeItem(at: f.vault.indexURL)
        try FileManager.default.removeItem(at: f.vault.previousIndexURL)
        let store = f.vault.makeStore()
        let report = try await store.open()
        #expect(report.indexSource == .recovered)
        #expect(report.recoveredFromPages)
        #expect(try await recoveredPages(store) == f.pagesByDocument)
    }

    @Test func unreadablePageIsSkippedAndKept() async throws {
        let f = try await makeVault()
        let victim = try #require(try f.vault.pageFiles().first)
        var bytes = try Data(contentsOf: victim)
        bytes[bytes.count - 1] ^= 0xFF
        try bytes.write(to: victim)
        try Data("x".utf8).write(to: f.vault.indexURL)
        try Data("x".utf8).write(to: f.vault.previousIndexURL)

        let store = f.vault.makeStore()
        let report = try await store.open()
        #expect(report.indexSource == .recovered)
        #expect(report.unreadablePages == 1)
        #expect(FileManager.default.fileExists(atPath: victim.path))  // never deleted
        let recovered = try await recoveredPages(store).values.reduce(0) { $0 + $1.count }
        #expect(recovered == 2)
    }

    @Test func wrongVaultKeyChangesNothing() async throws {
        let f = try await makeVault()
        let header = try f.vault.header()
        let before = try f.vault.allFiles().map { ($0.path, try Data(contentsOf: $0)) }
        await f.vault.keyStore.setKey(VaultCrypto.newKey(), for: header.vaultId)

        await #expect(throws: VaultError.vaultUnreadable) { try await f.vault.makeStore().open() }
        let afterFiles = try f.vault.allFiles().map { ($0.path, try Data(contentsOf: $0)) }
        #expect(afterFiles.map(\.0).sorted() == before.map(\.0).sorted())
        for (path, data) in before {
            #expect(afterFiles.first { $0.0 == path }?.1 == data, "\(URL(filePath: path).lastPathComponent) changed")
        }
    }

    // MARK: Orphaned page files

    func makeOrphans() async throws -> (TestVault, [URL]) {
        let vault = try TestVault()
        let store = vault.makeStore()
        try await store.open()
        _ = try await store.createDocument(type: .ktp, expiry: nil, pinned: false,
                                           fields: Synthetic.ktpFields, pages: [Synthetic.page("keep")])
        let existing = Set(try vault.pageFiles())
        let crash = CrashSwitch(crashAt: 1)  // stop right after the new pages are written
        let crashing = vault.makeStore(crash: crash)
        try await crashing.open()
        crash.arm()
        await #expect(throws: SimulatedCrash.self) {
            try await crashing.createDocument(type: .sim, expiry: nil, pinned: false, fields: DocumentFields(),
                                              pages: [Synthetic.page("o1"), Synthetic.page("o2")])
        }
        let orphans = try vault.pageFiles().filter { !existing.contains($0) }
        #expect(orphans.count == 2)
        return (vault, orphans)
    }

    @Test func oldOrphanedPagesAreDeleted() async throws {
        let (vault, orphans) = try await makeOrphans()
        vault.clock.advance(by: 6 * 60)
        let report = try await vault.makeStore().open()
        #expect(report.removedOrphanPages == 2)
        for url in orphans { #expect(!FileManager.default.fileExists(atPath: url.path)) }
        #expect(try vault.pageFiles().count == 1)
    }

    @Test func recentOrphanedPagesAreKept() async throws {
        let (vault, orphans) = try await makeOrphans()
        vault.clock.advance(by: 60)
        let report = try await vault.makeStore().open()
        #expect(report.removedOrphanPages == 0)
        for url in orphans { #expect(FileManager.default.fileExists(atPath: url.path)) }
    }

    @Test func unreadableOrphanIsNeverDeleted() async throws {
        let vault = try TestVault()
        try await vault.makeStore().open()
        let stray = vault.pageURL(PageID())
        try Data("not a page".utf8).write(to: stray)
        vault.clock.advance(by: 3600)
        let report = try await vault.makeStore().open()
        #expect(report.removedOrphanPages == 0)
        #expect(report.unreadablePages == 1)
        #expect(FileManager.default.fileExists(atPath: stray.path))
    }

    @Test func missingHeaderWithVaultFilesIsRefused() async throws {
        let f = try await makeVault()
        try FileManager.default.removeItem(at: f.vault.headerURL)
        await #expect(throws: VaultError.vaultHeaderMissing) { try await f.vault.makeStore().open() }
        #expect(await f.vault.keyStore.createCount == 1)  // only the original vault's key
    }
}
