//
//  FlushFailureTests.swift
//  VaultCoreTests
//
//  Created by Inez Amanda on 15/11/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import Testing

@testable import VaultCore

/// What a save does when a flush fails. Before the index is written, the save fails. After it,
/// the save counts, and only what depends on the flush is skipped.
@Suite("A flush that fails")
struct FlushFailureTests: FlushTesting {
    /// Adds a page with the flusher failing at `target`, and expects the save to fail with both
    /// index files and the store's documents as they were. The new page file isn't checked: it
    /// stays until a later open's orphan cleanup.
    func expectFailedSaveLeavesTheIndexAlone(failingAt target: (TestVault) -> RecordingFlusher.Target) async throws {
        let vault = try TestVault()
        let flusher = RecordingFlusher(pagesDirectory: vault.pagesDirectory, failingAt: target(vault))
        let store = try await makeStore(vault, flusher)
        let id = try await store.createDocument(
            type: .ktp, expiry: nil, pinned: false, fields: Synthetic.ktpFields, pages: [Synthetic.page("front")])
        let index = try Data(contentsOf: vault.indexURL)
        let previous = try Data(contentsOf: vault.previousIndexURL)
        let documents = try await store.snapshot()

        flusher.arm()
        await #expect(throws: FlushError.self) { _ = try await store.addPage(Synthetic.page("back"), to: id) }
        #expect(try Data(contentsOf: vault.indexURL) == index)
        #expect(try Data(contentsOf: vault.previousIndexURL) == previous)
        #expect(try await store.snapshot() == documents)
    }

    @Test func failedPageFlushFailsTheSaveAndLeavesTheIndexAlone() async throws {
        try await expectFailedSaveLeavesTheIndexAlone { _ in .pageFiles }
    }

    @Test func failedPagesFolderFlushFailsTheSaveAndLeavesTheIndexAlone() async throws {
        try await expectFailedSaveLeavesTheIndexAlone { .file($0.pagesDirectory) }
    }

    /// A failed index flush skips only the deletions. The index is already written, so the save
    /// counts, the projection is still written, and a later open removes the old page.
    @Test func failedIndexFlushKeepsTheSaveAndOnlySkipsTheDeletion() async throws {
        let vault = try TestVault()
        let flusher = RecordingFlusher(pagesDirectory: vault.pagesDirectory, failingAt: .file(vault.indexURL))
        let store = try await makeStore(vault, flusher)
        let id = try await store.createDocument(
            type: .ktp, expiry: nil, pinned: false, fields: Synthetic.ktpFields,
            pages: [Synthetic.page("front")])
        let old = try await store.document(id).pageIDs[0]
        try FileManager.default.removeItem(at: vault.projectionURL)

        flusher.arm()
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
        let flusher = RecordingFlusher(pagesDirectory: vault.pagesDirectory, failingAt: .file(vault.root))
        let store = try await makeStore(vault, flusher)
        let id = try await store.createDocument(
            type: .ktp, expiry: nil, pinned: false, fields: Synthetic.ktpFields,
            pages: [Synthetic.page("front")])
        let old = try await store.document(id).pageIDs[0]
        flusher.arm()
        var new: PageID?
        let saved = try await flushes(of: flusher) {
            new = try await store.replacePage(old, of: id, with: Synthetic.page("front-rescan"))
        }
        expectFlushOrder(saved, vault, newPages: [try #require(new)])
        #expect(FileManager.default.fileExists(atPath: vault.pageURL(old).path))
    }

    /// Two edits while index flushes fail, then one that flushes, then one more. Only an index that
    /// reached the disk becomes index.prev.enc.
    @Test func anIndexWhoseFlushFailedIsNeverMovedToThePreviousIndex() async throws {
        let vault = try TestVault()
        let flusher = RecordingFlusher(pagesDirectory: vault.pagesDirectory, failingAt: .file(vault.indexURL))
        let store = try await makeStore(vault, flusher)
        let id = try await store.createDocument(
            type: .ktp, expiry: nil, pinned: false, fields: Synthetic.ktpFields, pages: [])
        let onDisk = try Data(contentsOf: vault.indexURL)  // flushed, so the first edit moves it
        func edit(label: String) async throws {
            try await store.editDocument(
                id, type: .ktp, label: label, expiry: nil, pinned: false, fields: Synthetic.ktpFields)
        }

        flusher.arm()
        try await edit(label: "a")
        try await edit(label: "b")
        #expect(try Data(contentsOf: vault.previousIndexURL) == onDisk)
        flusher.disarm()
        try await edit(label: "c")  // replaces the unflushed index, and this time it's flushed
        #expect(try Data(contentsOf: vault.previousIndexURL) == onDisk)
        let flushed = try Data(contentsOf: vault.indexURL)
        try await edit(label: "d")
        #expect(try Data(contentsOf: vault.previousIndexURL) == flushed)
    }

    @Test func failedFlushDuringThePurgeInOpenStillOpens() async throws {
        let vault = try TestVault()
        let store = vault.makeStore()
        try await store.open()
        let id = try await store.createDocument(
            type: .ktp, expiry: nil, pinned: false, fields: Synthetic.ktpFields,
            pages: [Synthetic.page("front"), Synthetic.page("back")])
        let sealedKey = try #require(try await vault.readIndex(at: vault.indexURL).documents.first).sealedKey
        try await store.delete(id)
        let pages = try vault.pageFiles()
        vault.clock.advance(by: 31 * 86400)

        let flusher = RecordingFlusher(pagesDirectory: vault.pagesDirectory, failingAt: .file(vault.indexURL))
        flusher.arm()
        let report = try await vault.makeStore(flusher: flusher).open()
        #expect(report.purgedDocuments == 1)
        // The purged pages, with their sealed key, wait for the next open's cleanup.
        #expect(try vault.pageFiles() == pages)

        let next = try await vault.makeStore().open()
        #expect(next.removedOrphanPages == pages.count)
        #expect(try vault.pageFiles().isEmpty)
        try await expectNoIndexHolds(sealedKey, in: vault)
    }

    /// The first index write of a purge isn't flushed, so its pages wait for the second write, which
    /// doesn't move the unflushed one to index.prev.enc. Once that write is on disk they go.
    @Test func failedFirstPurgeFlushDeletesThePagesAfterTheSecondWrite() async throws {
        let vault = try TestVault()
        let flusher = RecordingFlusher(pagesDirectory: vault.pagesDirectory, failingAt: .file(vault.indexURL))
        let store = try await makeStore(vault, flusher)
        let id = try await store.createDocument(
            type: .ktp, expiry: nil, pinned: false, fields: Synthetic.ktpFields,
            pages: [Synthetic.page("front"), Synthetic.page("back")])
        let other = try await store.createDocument(
            type: .sim, expiry: nil, pinned: false, fields: Synthetic.simFields, pages: [])
        let sealedKey = try #require(try await vault.readIndex(at: vault.indexURL).documents.first { $0.id == id })
            .sealedKey
        try await store.delete(id)
        let onDisk = try Data(contentsOf: vault.indexURL)

        flusher.arm(times: 1)
        let events = try await flushes(of: flusher) { try await store.deletePermanently(id) }
        await #expect(throws: VaultError.documentNotFound) { try await store.document(id) }
        #expect(try vault.pageFiles().isEmpty)
        #expect(events.last.map { path($0.url) } == path(vault.pagesDirectory))
        #expect(try Data(contentsOf: vault.previousIndexURL) == onDisk)

        // The next save moves the purged index over the one that still held the key.
        try await store.editDocument(
            other, type: .sim, label: "x", expiry: nil, pinned: false, fields: Synthetic.simFields)
        try await expectNoIndexHolds(sealedKey, in: vault)
    }

    /// Both purge flushes failed, so the pages are still there at the next open. They go before the
    /// open writes its repair, so a repair cut short can't re-attach them.
    @Test func orphanPagesGoBeforeTheRepairAtOpen() async throws {
        let vault = try TestVault()
        let flusher = RecordingFlusher(pagesDirectory: vault.pagesDirectory, failingAt: .file(vault.indexURL))
        let store = try await makeStore(vault, flusher)
        let id = try await store.createDocument(
            type: .ktp, expiry: nil, pinned: false, fields: Synthetic.ktpFields, pages: [Synthetic.page("front")])
        try await store.delete(id)
        flusher.arm()
        try await store.deletePermanently(id)
        try #require(try !vault.pageFiles().isEmpty)

        vault.clock.advance(by: 3600)
        let crash = CrashSwitch(crashAt: 1)  // the repair's first write step
        crash.arm()
        await #expect(throws: SimulatedCrash.self) { try await vault.makeStore(crash: crash).open() }
        #expect(crash.steps == [.pagesWritten])
        #expect(try vault.pageFiles().isEmpty)
    }

    /// Only the second index write of a purge isn't flushed. The pages went after the first, which
    /// reached the disk and is now index.prev.enc; the next save replaces the unflushed index.enc.
    @Test func failedSecondPurgeFlushHasAlreadyDeletedThePages() async throws {
        let vault = try TestVault()
        let flusher = RecordingFlusher(pagesDirectory: vault.pagesDirectory, failingAt: .file(vault.indexURL))
        let store = try await makeStore(vault, flusher)
        let id = try await store.createDocument(
            type: .ktp, expiry: nil, pinned: false, fields: Synthetic.ktpFields, pages: [Synthetic.page("front")])
        let other = try await store.createDocument(
            type: .sim, expiry: nil, pinned: false, fields: Synthetic.simFields, pages: [])
        let sealedKey = try #require(try await vault.readIndex(at: vault.indexURL).documents.first { $0.id == id })
            .sealedKey
        try await store.delete(id)

        flusher.arm(times: 1, skipping: 1)
        try await store.deletePermanently(id)
        #expect(try vault.pageFiles().isEmpty)
        let purged = try Data(contentsOf: vault.previousIndexURL)
        try await expectNoIndexHolds(sealedKey, in: vault)

        try await store.editDocument(
            other, type: .sim, label: "x", expiry: nil, pinned: false, fields: Synthetic.simFields)
        #expect(try Data(contentsOf: vault.previousIndexURL) == purged)
    }

    /// Like an index flush, a header flush that fails doesn't stop a new vault.
    /// vault.json is written once, so no later write repeats its flush: a save flushes it first
    /// while that hasn't worked, and fails rather than store a document beside a header that may
    /// come back empty.
    @Test func aSaveFailsUntilTheHeaderReachesTheDisk() async throws {
        let vault = try TestVault()
        let flusher = RecordingFlusher(pagesDirectory: vault.pagesDirectory, failingAt: .file(vault.headerURL))
        flusher.arm()
        let store = vault.makeStore(flusher: flusher)
        #expect(try await store.open().createdVault)
        await #expect(throws: FlushError.self) {
            _ = try await store.createDocument(
                type: .ktp, expiry: nil, pinned: false, fields: Synthetic.ktpFields, pages: [Synthetic.page("front")])
        }
        #expect(try await store.documents().isEmpty)
        #expect(try vault.pageFiles().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: vault.indexURL.path))

        flusher.disarm()
        let id = try await store.createDocument(
            type: .ktp, expiry: nil, pinned: false, fields: Synthetic.ktpFields, pages: [Synthetic.page("front")])
        try await store.editDocument(id, type: .ktp, label: nil, expiry: nil, pinned: true, fields: Synthetic.ktpFields)
        // Flushed once, by the first save that worked.
        #expect(flusher.recorded.filter { path($0.url) == path(vault.headerURL) && !$0.failed }.count == 1)
        let reopened = vault.makeStore()
        try await reopened.open()
        #expect(try await reopened.document(id).pinned)
    }

    /// With the header flush failing, a new vault's open writes no index.enc, so the next open
    /// finds vault.json alone: an empty vault, not a damaged one.
    @Test func aNewVaultWhoseHeaderFlushFailedReopensEmpty() async throws {
        let vault = try TestVault()
        let failing = RecordingFlusher(pagesDirectory: vault.pagesDirectory, failingAt: .file(vault.headerURL))
        failing.arm()
        #expect(try await vault.makeStore(flusher: failing).open().createdVault)

        let report = try await vault.makeStore(flusher: failing).open()
        #expect(!report.createdVault && !report.recoveredFromPages && !report.newestChangeMayBeLost)
        let reopened = vault.makeStore()
        try await reopened.open()
        #expect(try await reopened.documents().isEmpty)
        #expect(FileManager.default.fileExists(atPath: vault.indexURL.path))
    }

    @Test func aFailedHeaderFlushAtOpenStillOpensAndReads() async throws {
        let vault = try TestVault()
        let first = vault.makeStore()
        try await first.open()
        let id = try await first.createDocument(
            type: .ktp, expiry: nil, pinned: false, fields: Synthetic.ktpFields, pages: [Synthetic.page("front")])

        let flusher = RecordingFlusher(pagesDirectory: vault.pagesDirectory, failingAt: .file(vault.headerURL))
        flusher.arm()
        let store = vault.makeStore(flusher: flusher)
        try await store.open()
        #expect(try await store.fields(of: id) == Synthetic.ktpFields)
        #expect(try await store.pages(of: id).map(\.data) == [Synthetic.page("front")])
        await #expect(throws: FlushError.self) {
            try await store.editDocument(
                id, type: .ktp, label: nil, expiry: nil, pinned: true, fields: Synthetic.ktpFields)
        }
        #expect(try await !store.document(id).pinned)
    }

    /// The purge writes the index twice; with the header's flush failing it waits for an open
    /// where it works, so the open itself never fails over it.
    @Test func aFailedHeaderFlushAtOpenPutsOffThePurge() async throws {
        let vault = try TestVault()
        let store = vault.makeStore()
        try await store.open()
        let id = try await store.createDocument(
            type: .ktp, expiry: nil, pinned: false, fields: Synthetic.ktpFields, pages: [Synthetic.page("front")])
        try await store.delete(id)
        vault.clock.advance(by: 31 * 86400)

        let flusher = RecordingFlusher(pagesDirectory: vault.pagesDirectory, failingAt: .file(vault.headerURL))
        flusher.arm()
        let waiting = vault.makeStore(flusher: flusher)
        #expect(try await waiting.open().purgedDocuments == 0)
        #expect(try await waiting.recentlyDeleted().map(\.id) == [id])

        #expect(try await vault.makeStore().open().purgedDocuments == 1)
    }

    /// index.enc is damaged, so the open writes a new one from index.prev.enc. Its flush fails,
    /// so the next save replaces it rather than moving it to index.prev.enc.
    @Test func failedFlushDuringTheRepairOnOpenStillOpens() async throws {
        let vault = try TestVault()
        let store = vault.makeStore()
        try await store.open()
        let id = try await store.createDocument(
            type: .ktp, expiry: nil, pinned: false, fields: Synthetic.ktpFields, pages: [])
        try await store.editDocument(id, type: .ktp, label: nil, expiry: nil, pinned: true, fields: Synthetic.ktpFields)
        var damaged = try Data(contentsOf: vault.indexURL)
        damaged[damaged.count / 2] ^= 0xFF
        try damaged.write(to: vault.indexURL)
        let onDisk = try Data(contentsOf: vault.previousIndexURL)

        let flusher = RecordingFlusher(pagesDirectory: vault.pagesDirectory, failingAt: .file(vault.indexURL))
        flusher.arm()
        let repaired = vault.makeStore(flusher: flusher)
        let report = try await repaired.open()
        #expect(report.indexSource == .previous)
        #expect(try Data(contentsOf: vault.indexURL) != damaged)

        flusher.disarm()
        try await repaired.editDocument(
            id, type: .ktp, label: "x", expiry: nil, pinned: false, fields: Synthetic.ktpFields)
        #expect(try Data(contentsOf: vault.previousIndexURL) == onDisk)
    }
}
