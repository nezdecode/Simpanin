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

/// Every save flushes before it returns: its new page files and the pages folder when it wrote
/// any, then the index and the vault folder. A purge flushes after each of its two index writes.
@Suite("Flushing every save")
struct FlushTests: FlushTesting {
    func generation(of sealedIndex: Data, in vault: TestVault) async throws -> VaultIndex {
        let header = try vault.header()
        let key = try #require(await vault.keyStore.key(for: header.vaultID))
        let plain = try VaultCrypto.open(
            sealedIndex, with: VaultCrypto.indexKey(from: key, vaultID: header.vaultID),
            as: .index(header.vaultID))
        return try VaultJSON.decoder.decode(VaultIndex.self, from: plain)
    }

    @Test func everySaveFlushesTheIndexAndTheVaultFolder() async throws {
        let vault = try TestVault()
        let flusher = RecordingFlusher(pagesDirectory: vault.pagesDirectory)
        let store = try await makeStore(vault, flusher)
        var id: DocumentID?
        var saved = try await flushes(of: flusher) {
            id = try await store.createDocument(
                type: .ktp, expiry: nil, pinned: false,
                fields: Synthetic.ktpFields, pages: [Synthetic.page("k")])
        }
        let ktp = try #require(id)
        expectFlushOrder(saved, vault, newPages: try await store.document(ktp).pageIDs)

        saved = try await flushes(of: flusher) {
            try await store.editDocument(
                ktp, type: .ktp, label: nil, expiry: nil, pinned: true, fields: Synthetic.ktpFields)
        }
        expectFlushOrder(saved, vault, newPages: [])
        var added: PageID?
        saved = try await flushes(of: flusher) { added = try await store.addPage(Synthetic.page("k2"), to: ktp) }
        expectFlushOrder(saved, vault, newPages: [try #require(added)])
        saved = try await flushes(of: flusher) { try await store.delete(ktp) }
        expectFlushOrder(saved, vault, newPages: [])
        saved = try await flushes(of: flusher) { try await store.restore(ktp) }
        expectFlushOrder(saved, vault, newPages: [])
        #expect(await store.lastFlushMethod == .fullFsync)
    }

    /// No index ever names a page that hasn't reached the disk.
    @Test func newPagesAreFlushedBeforeTheIndexIsWritten() async throws {
        let vault = try TestVault()
        let flusher = RecordingFlusher(pagesDirectory: vault.pagesDirectory)
        let store = try await makeStore(vault, flusher)
        let indexBefore = try Data(contentsOf: vault.indexURL)
        let saved = try await flushes(of: flusher) {
            _ = try await store.createDocument(
                type: .ktp, expiry: nil, pinned: false, fields: Synthetic.ktpFields,
                pages: [Synthetic.page("front"), Synthetic.page("back")])
        }
        try #require(saved.count == 5)
        for event in saved.prefix(3) { #expect(event.indexContents == indexBefore) }
        #expect(saved[3].contents != indexBefore)
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
        var replaced: PageID?
        let events = try await flushes(of: flusher) {
            replaced = try await store.replacePage(old, of: id, with: Synthetic.page("front-rescan"))
        }
        let new = try #require(replaced)

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

    func indexPairs(_ vault: TestVault) -> [String] {
        [vault.indexURL, vault.root, vault.indexURL, vault.root].map(path)
    }

    /// The pages go between the two index writes, so a cut-short second write can't bring them back.
    @Test func purgeFlushesAfterEachIndexWriteAndDeletesItsPagesBetweenThem() async throws {
        let vault = try TestVault()
        let flusher = RecordingFlusher(pagesDirectory: vault.pagesDirectory)
        let store = try await makeStore(vault, flusher)
        let id = try await store.createDocument(
            type: .ktp, expiry: nil, pinned: false, fields: Synthetic.ktpFields,
            pages: [Synthetic.page("p1"), Synthetic.page("p2")])
        let pages = try await store.document(id).pageIDs.map { "\($0.string).enc" }
        try await store.delete(id)
        let generationBefore = try await vault.readIndex(at: vault.indexURL).generation
        let events = try await flushes(of: flusher) { try await store.deletePermanently(id) }

        // The pages folder is flushed after the deletions, so they reach the disk before the second write.
        let expected = [vault.indexURL, vault.root, vault.pagesDirectory, vault.indexURL, vault.root].map(path)
        #expect(events.map { path($0.url) } == expected)
        try #require(events.count == 5)
        let first = try await generation(of: events[0].contents, in: vault)
        #expect(first.generation == generationBefore + 1)
        #expect(first.documents.isEmpty)
        #expect(try await generation(of: events[3].contents, in: vault).generation == generationBefore + 2)
        for page in pages {
            #expect(events[0].pageFiles.contains(page) && events[1].pageFiles.contains(page))
            #expect(events[2...].allSatisfy { !$0.pageFiles.contains(page) })
        }
    }

    @Test func purgeOfADocumentWithoutPagesFlushesBothIndexWrites() async throws {
        let vault = try TestVault()
        let flusher = RecordingFlusher(pagesDirectory: vault.pagesDirectory)
        let store = try await makeStore(vault, flusher)
        let id = try await store.createDocument(
            type: .npwp, expiry: nil, pinned: false,
            fields: DocumentFields(["number": "00.000.000.0-000.000"]), pages: [])
        try await store.delete(id)
        let events = try await flushes(of: flusher) { try await store.deletePermanently(id) }
        #expect(events.map { path($0.url) } == indexPairs(vault))
    }

    @Test func obsoletePageAlreadyGoneStillFlushes() async throws {
        let vault = try TestVault()
        let flusher = RecordingFlusher(pagesDirectory: vault.pagesDirectory)
        let store = try await makeStore(vault, flusher)
        let id = try await store.createDocument(
            type: .ktp, expiry: nil, pinned: false, fields: Synthetic.ktpFields,
            pages: [Synthetic.page("front")])
        let old = try await store.document(id).pageIDs[0]
        try FileManager.default.removeItem(at: vault.pageURL(old))
        var new: PageID?
        let events = try await flushes(of: flusher) {
            new = try await store.replacePage(old, of: id, with: Synthetic.page("front-rescan"))
        }
        expectFlushOrder(events, vault, newPages: [try #require(new)])
    }

    /// Without this, a power cut soon after the first save could leave an empty vault.json beside
    /// a good index. Opening an existing vault writes and flushes nothing.
    @Test func aNewVaultFlushesItsHeaderAndFolders() async throws {
        let vault = try TestVault()
        let flusher = RecordingFlusher(pagesDirectory: vault.pagesDirectory)
        _ = try await makeStore(vault, flusher)
        let header = [vault.headerURL, vault.root, vault.root.deletingLastPathComponent()].map(path)
        // Then the first, empty index.
        #expect(flusher.recorded.map { path($0.url) } == header + [path(vault.indexURL), path(vault.root)])
        #expect(flusher.recorded.first?.contents == (try Data(contentsOf: vault.headerURL)))

        let reopening = RecordingFlusher(pagesDirectory: vault.pagesDirectory)
        _ = try await makeStore(vault, reopening)
        #expect(reopening.recorded.isEmpty)
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
        #expect(throws: FlushFailed()) { try flusher.flush(url) }
    }

    @Test func missingFileFailsToFlush() {
        let url = FileManager.default.temporaryDirectory.appending(path: "missing-\(UUID().uuidString).bin")
        #expect(throws: FlushFailed()) { try FileSystemFlusher().flush(url) }
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
