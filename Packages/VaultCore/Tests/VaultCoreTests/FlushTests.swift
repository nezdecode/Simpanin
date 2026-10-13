//
//  FlushTests.swift
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

/// Before step 3 deletes anything, the new pages, the pages folder, the index and the vault
/// folder are flushed, in that order.
@Suite("Index flush before deleting pages")
struct FlushTests {
    struct FlushError: Error {}

    func makeStore(_ vault: TestVault, _ flusher: RecordingFlusher) async throws -> VaultStore {
        let store = vault.makeStore(flusher: flusher)
        try await store.open()
        return store
    }

    func path(_ url: URL) -> String { url.standardizedFileURL.path }

    /// The flushes of one commit, in order. Each new page file, then the pages folder, the new
    /// index file and the vault folder.
    func expectFlushOrder(_ events: [RecordingFlusher.Event], _ vault: TestVault, newPages: [PageID]) {
        let expected =
            newPages.map { path(vault.pageURL($0)) }
            + [path(vault.pagesDirectory), path(vault.indexURL), path(vault.root)]
        #expect(events.map { path($0.url) } == expected)
    }

    func generation(of sealedIndex: Data, in vault: TestVault) async throws -> VaultIndex {
        let header = try vault.header()
        let key = try #require(await vault.keyStore.key(for: header.vaultID))
        let plain = try VaultCrypto.open(
            sealedIndex, with: VaultCrypto.indexKey(from: key, vaultID: header.vaultID),
            as: .index(header.vaultID))
        return try VaultJSON.decoder.decode(VaultIndex.self, from: plain)
    }

    @Test func noFlushWhenNothingIsDeleted() async throws {
        let vault = try TestVault()
        let flusher = RecordingFlusher(pagesDirectory: vault.pagesDirectory)
        let store = try await makeStore(vault, flusher)
        let id = try await store.createDocument(
            type: .ktp, expiry: nil, pinned: false,
            fields: Synthetic.ktpFields, pages: [Synthetic.page("k")])
        try await store.editDocument(id, type: .ktp, expiry: nil, pinned: true, fields: Synthetic.ktpFields)
        _ = try await store.addPage(Synthetic.page("k2"), to: id)
        try await store.delete(id)
        try await store.restore(id)
        #expect(flusher.recorded.isEmpty)
        #expect(await store.lastFlushMethod == nil)
    }

    @Test func replacePageFlushesNewPageThenPagesFolderThenIndexThenVaultFolder() async throws {
        let vault = try TestVault()
        let flusher = RecordingFlusher(pagesDirectory: vault.pagesDirectory)
        let store = try await makeStore(vault, flusher)
        let id = try await store.createDocument(
            type: .ktp, expiry: nil, pinned: false, fields: Synthetic.ktpFields,
            pages: [Synthetic.page("front"), Synthetic.page("back")])
        let generationBefore = try await vault.readIndex(at: vault.indexURL).generation
        let old = try await store.document(id).pageIDs[0]
        let new = try await store.replacePage(old, of: id, with: Synthetic.page("front-rescan"))

        let events = flusher.recorded
        try #require(events.count == 4)
        // The new page is flushed first, so the index never points to a page lost in a power cut.
        expectFlushOrder(events, vault, newPages: [new])
        #expect(events[0].contents == (try Data(contentsOf: vault.pageURL(new))))
        // The index flushed is the new generation, pointing at the new page...
        let flushed = try await generation(of: events[2].contents, in: vault)
        #expect(flushed.generation == generationBefore + 1)
        #expect(flushed.documents.first?.pageIDs.first == new)
        // ...and the old page still existed at every flush.
        for event in events { #expect(event.pageFiles.contains("\(old.string).enc")) }
        #expect(!FileManager.default.fileExists(atPath: vault.pageURL(old).path))
        #expect(await store.lastFlushMethod == .fullFsync)
    }

    @Test func purgeFlushesAfterBothIndexWrites() async throws {
        let vault = try TestVault()
        let flusher = RecordingFlusher(pagesDirectory: vault.pagesDirectory)
        let store = try await makeStore(vault, flusher)
        let id = try await store.createDocument(
            type: .ktp, expiry: nil, pinned: false, fields: Synthetic.ktpFields,
            pages: [Synthetic.page("p1"), Synthetic.page("p2")])
        let pages = try await store.document(id).pageIDs
        let generationBefore = try await vault.readIndex(at: vault.indexURL).generation
        try await store.deletePermanently(id)

        let events = flusher.recorded
        try #require(events.count == 3)
        expectFlushOrder(events, vault, newPages: [])  // a purge writes no page in step 1
        let flushed = try await generation(of: events[1].contents, in: vault)
        #expect(flushed.generation == generationBefore + 2)
        #expect(flushed.documents.isEmpty)
        for page in pages { #expect(events[2].pageFiles.contains("\(page.string).enc")) }
    }

    @Test func purgeOfADocumentWithoutPagesDoesNotFlush() async throws {
        let vault = try TestVault()
        let flusher = RecordingFlusher(pagesDirectory: vault.pagesDirectory)
        let store = try await makeStore(vault, flusher)
        let id = try await store.createDocument(
            type: .npwp, expiry: nil, pinned: false,
            fields: DocumentFields(["number": "00.000.000.0-000.000"]), pages: [])
        try await store.deletePermanently(id)
        #expect(flusher.recorded.isEmpty)
    }

    @Test func obsoletePageAlreadyGoneDoesNotFlush() async throws {
        let vault = try TestVault()
        let flusher = RecordingFlusher(pagesDirectory: vault.pagesDirectory)
        let store = try await makeStore(vault, flusher)
        let id = try await store.createDocument(
            type: .ktp, expiry: nil, pinned: false, fields: Synthetic.ktpFields,
            pages: [Synthetic.page("front")])
        let old = try await store.document(id).pageIDs[0]
        try FileManager.default.removeItem(at: vault.pageURL(old))
        _ = try await store.replacePage(old, of: id, with: Synthetic.page("front-rescan"))
        #expect(flusher.recorded.isEmpty)
    }

    /// A failed flush skips only the deletions. The index is already written, so the save
    /// counts, the projection is still written, and a later open removes the old page.
    @Test func failedFlushKeepsTheSaveAndOnlySkipsTheDeletion() async throws {
        let vault = try TestVault()
        let flusher = RecordingFlusher(pagesDirectory: vault.pagesDirectory, failure: FlushError())
        let store = try await makeStore(vault, flusher)
        let id = try await store.createDocument(
            type: .ktp, expiry: nil, pinned: false, fields: Synthetic.ktpFields,
            pages: [Synthetic.page("front")])
        let old = try await store.document(id).pageIDs[0]
        try FileManager.default.removeItem(at: vault.projectionURL)

        _ = try await store.replacePage(old, of: id, with: Synthetic.page("front-rescan"))
        #expect(try await store.pages(of: id).map(\.data) == [Synthetic.page("front-rescan")])
        #expect(FileManager.default.fileExists(atPath: vault.pageURL(old).path))
        #expect(FileManager.default.fileExists(atPath: vault.projectionURL.path))

        vault.clock.advance(by: 3600)
        let reopened = vault.makeStore()
        let report = try await reopened.open()
        #expect(report.indexSource == .current)
        #expect(try await reopened.pages(of: id).map(\.data) == [Synthetic.page("front-rescan")])
        #expect(!FileManager.default.fileExists(atPath: vault.pageURL(old).path))
    }

    @Test func failedDirectoryFlushOnlySkipsTheDeletion() async throws {
        let vault = try TestVault()
        let flusher = RecordingFlusher(
            pagesDirectory: vault.pagesDirectory, failure: FlushError(),
            failOnlyAt: vault.root)
        let store = try await makeStore(vault, flusher)
        let id = try await store.createDocument(
            type: .ktp, expiry: nil, pinned: false, fields: Synthetic.ktpFields,
            pages: [Synthetic.page("front")])
        let old = try await store.document(id).pageIDs[0]
        let new = try await store.replacePage(old, of: id, with: Synthetic.page("front-rescan"))
        expectFlushOrder(flusher.recorded, vault, newPages: [new])
        #expect(FileManager.default.fileExists(atPath: vault.pageURL(old).path))
    }

    @Test func failedPagesFolderFlushStopsBeforeTheIndex() async throws {
        let vault = try TestVault()
        let flusher = RecordingFlusher(
            pagesDirectory: vault.pagesDirectory, failure: FlushError(),
            failOnlyAt: vault.pagesDirectory)
        let store = try await makeStore(vault, flusher)
        let id = try await store.createDocument(
            type: .ktp, expiry: nil, pinned: false, fields: Synthetic.ktpFields,
            pages: [Synthetic.page("front")])
        let old = try await store.document(id).pageIDs[0]
        let new = try await store.replacePage(old, of: id, with: Synthetic.page("front-rescan"))
        #expect(flusher.recorded.map { path($0.url) } == [path(vault.pageURL(new)), path(vault.pagesDirectory)])
        #expect(FileManager.default.fileExists(atPath: vault.pageURL(old).path))
    }

    @Test func failedFlushDuringThePurgeInOpenStillOpens() async throws {
        let vault = try TestVault()
        let store = vault.makeStore()
        try await store.open()
        let id = try await store.createDocument(
            type: .ktp, expiry: nil, pinned: false, fields: Synthetic.ktpFields,
            pages: [Synthetic.page("front"), Synthetic.page("back")])
        try await store.delete(id)
        let pages = try vault.pageFiles()
        vault.clock.advance(by: 31 * 86400)

        let flusher = RecordingFlusher(pagesDirectory: vault.pagesDirectory, failure: FlushError())
        let report = try await vault.makeStore(flusher: flusher).open()
        #expect(report.purgedDocuments == 1)
        // The purged pages, with their sealed key, wait for the next open's cleanup.
        #expect(try vault.pageFiles() == pages)

        let next = try await vault.makeStore().open()
        #expect(next.removedOrphanPages == pages.count)
        #expect(try vault.pageFiles().isEmpty)
    }

    @Test func recordsTheWeakerMethodWhenTheTwoFlushesDiffer() async throws {
        // The index got F_FULLFSYNC but the folder only fsync, so the weaker one is recorded.
        let vault = try TestVault()
        let root = vault.root.standardizedFileURL.path
        let flusher = RecordingFlusher(
            pagesDirectory: vault.pagesDirectory,
            method: { $0.standardizedFileURL.path == root ? .fsync : .fullFsync })
        let store = try await makeStore(vault, flusher)
        let id = try await store.createDocument(
            type: .ktp, expiry: nil, pinned: false, fields: Synthetic.ktpFields,
            pages: [Synthetic.page("front")])
        _ = try await store.replacePage(try await store.document(id).pageIDs[0], of: id, with: Synthetic.page("x"))
        #expect(await store.lastFlushMethod == .fsync)
    }

    @Test func recordsTheMethodThatRan() async throws {
        let vault = try TestVault()
        let flusher = RecordingFlusher(pagesDirectory: vault.pagesDirectory, method: { _ in .fsync })
        let store = try await makeStore(vault, flusher)
        let id = try await store.createDocument(
            type: .ktp, expiry: nil, pinned: false, fields: Synthetic.ktpFields,
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

    @Test func failsWhenTheFallbackFailsToo() throws {
        let url = try tempFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let flusher = FileSystemFlusher(fullSync: { _ in -1 }, fileSync: { _ in -1 })
        #expect(throws: VaultError.flushFailed) { try flusher.flush(url) }
    }

    @Test func missingFileFailsToFlush() {
        let url = FileManager.default.temporaryDirectory.appending(path: "missing-\(UUID().uuidString).bin")
        #expect(throws: VaultError.flushFailed) { try FileSystemFlusher().flush(url) }
    }

    @Test func realDirectoryFlushOnThisMachine() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "flushdir-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let method = try FileSystemFlusher().flush(directory)
        print("DIRECTORY FLUSH METHOD ON THIS MACHINE: \(method)")
        #if canImport(Darwin)
            #expect(method == .fullFsync)
        #else
            #expect(method == .fsync)
        #endif
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
