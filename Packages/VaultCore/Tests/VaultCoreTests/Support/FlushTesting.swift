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

    /// The flushes of one commit, in order. Each new page file, then the pages folder, the new
    /// index file and the vault folder.
    func expectFlushOrder(_ events: [RecordingFlusher.Event], _ vault: TestVault, newPages: [PageID]) {
        let expected =
            newPages.map { path(vault.pageURL($0)) }
            + [path(vault.pagesDirectory), path(vault.indexURL), path(vault.root)]
        #expect(events.map { path($0.url) } == expected)
    }
}

struct FlushError: Error {}
