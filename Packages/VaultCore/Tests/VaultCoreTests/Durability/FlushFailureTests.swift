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

/// What a save does when a flush fails.
@Suite("A flush that fails")
struct FlushFailureTests: FlushTesting {
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
}
