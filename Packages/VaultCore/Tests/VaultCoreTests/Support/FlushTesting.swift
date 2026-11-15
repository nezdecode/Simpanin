//
//  FlushTesting.swift
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

/// Helpers shared by the suites that record flushes.
protocol FlushTesting {}

extension FlushTesting {
    func makeStore(_ vault: TestVault, _ flusher: RecordingFlusher) async throws -> VaultStore {
        let store = vault.makeStore(flusher: flusher)
        try await store.open()
        return store
    }

    func path(_ url: URL) -> String { url.standardizedFileURL.path }

    /// The flushes of one save, in order. Each new page file and the pages folder when it wrote
    /// pages, then the new index file and the vault folder.
    func expectFlushOrder(_ events: [RecordingFlusher.Event], _ vault: TestVault, newPages: [PageID]) {
        let pages = newPages.isEmpty ? [] : newPages.map { path(vault.pageURL($0)) } + [path(vault.pagesDirectory)]
        #expect(events.map { path($0.url) } == pages + [path(vault.indexURL), path(vault.root)])
    }

    /// The flushes `save` made.
    func flushes(
        of flusher: RecordingFlusher, during save: () async throws -> Void
    ) async throws -> [RecordingFlusher.Event] {
        let start = flusher.recorded.count
        try await save()
        return Array(flusher.recorded.dropFirst(start))
    }

    /// Neither index file still holds `sealedKey`.
    func expectNoIndexHolds(_ sealedKey: Data, in vault: TestVault) async throws {
        for url in [vault.indexURL, vault.previousIndexURL] where FileManager.default.fileExists(atPath: url.path) {
            let index = try await vault.readIndex(at: url)
            #expect(!index.documents.contains { $0.sealedKey == sealedKey }, "\(url.lastPathComponent)")
        }
    }
}

struct FlushError: Error {}
