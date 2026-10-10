//
//  VaultStore+WriteOrder.swift
//  VaultCore
//
//  Created by Inez Amanda on 10/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

extension VaultStore {
    // MARK: - The write order

    func commit(
        _ documents: [IndexEntry], newPages: [(PageID, Data)] = [],
        obsoletePages: [PageID] = [], writeIndexTwice: Bool = false
    ) throws {
        // 1. New page files.
        for (pageID, data) in newPages {
            try write(data, to: pageURL(pageID), protection: .complete)
        }
        try step(.pagesWritten)

        // 2. Rotate and write the index (twice for a purge).
        try writeIndex(documents)
        if writeIndexTwice { try writeIndex(documents) }

        // 3. Delete pages the index no longer references. First flush the new pages, the pages
        //    folder, the index and the vault folder, so nothing is deleted before its
        //    replacement is on disk.
        let fileManager = FileManager.default
        var doomed: [PageID] = []
        for pageID in obsoletePages where fileManager.fileExists(atPath: pageURL(pageID).path) {
            doomed.append(pageID)
        }
        if !doomed.isEmpty {
            do {
                var methods: [FlushMethod] = []
                for (pageID, _) in newPages {
                    methods.append(try flusher.flush(pageURL(pageID)))
                }
                methods.append(try flusher.flush(pagesDirectory))
                methods.append(try flusher.flush(indexURL))
                methods.append(try flusher.flush(root))
                // A commit is only as durable as its weakest flush.
                lastFlushMethod = methods.allSatisfy { $0 == .fullFsync } ? .fullFsync : .fsync
            } catch {
                throw VaultError.flushFailed
            }
        }
        for pageID in doomed {
            try fileManager.removeItem(at: pageURL(pageID))
        }
        try step(.obsoletePagesDeleted)

        // 4. Projection last.
        try writeProjection(documents)
        try step(.projectionWritten)
    }

    private func writeIndex(_ documents: [IndexEntry]) throws {
        var state = try requireState()
        let next = VaultIndex(generation: state.index.generation + 1, documents: documents)
        let sealed = try VaultCrypto.seal(
            VaultJSON.encoder.encode(next), with: state.indexKey,
            as: .index(state.header.vaultId))
        let fileManager = FileManager.default
        if state.indexFileIsCurrent, fileManager.fileExists(atPath: indexURL.path) {
            if fileManager.fileExists(atPath: previousIndexURL.path) {
                try fileManager.removeItem(at: previousIndexURL)
            }
            try fileManager.moveItem(at: indexURL, to: previousIndexURL)
        }
        try step(.indexMovedToPrevious)
        try write(sealed, to: indexURL, protection: .complete)
        state.index = next
        state.indexFileIsCurrent = true
        self.state = state
        try step(.indexWritten)
    }

    func writeProjection(_ documents: [IndexEntry]) throws {
        let projection = Projection(
            documents: documents.filter { $0.deletedAt == nil }.map {
                ProjectionEntry(id: $0.id, type: $0.type, expiry: $0.expiry, reminderOffsets: reminderOffsets)
            })
        try FileManager.default.createDirectory(
            at: projectionURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try write(
            VaultJSON.encoder.encode(projection), to: projectionURL,
            protection: .completeUntilFirstUserAuthentication)
    }

    func write(_ data: Data, to url: URL, protection: FileProtectionClass) throws {
        try data.write(to: url, options: .atomic)
        try fileProtector.protect(url, as: protection)
    }

    private func step(_ step: WriteStep) throws {
        try crashHook?(step)
    }
}
