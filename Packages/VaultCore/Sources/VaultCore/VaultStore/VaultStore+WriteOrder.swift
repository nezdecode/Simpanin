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

        // 2. Rotate and write the index (twice for a purge). Once index.enc is written the
        //    change is saved. Anything that fails after this is repaired by the next open().
        try writeIndex(documents)
        if writeIndexTwice { try afterSave { try writeIndex(documents) } }

        // 3. Delete pages the index no longer references. First flush the new pages, the pages
        //    folder, the index and the vault folder, so nothing is deleted before its
        //    replacement is on disk. If a flush fails, the save still counts because the index
        //    is written. The old pages just stay until orphan cleanup on a later open.
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
                doomed = []
            }
        }
        for pageID in doomed {
            try afterSave { try FileManager.default.removeItem(at: pageURL(pageID)) }
        }
        try step(.obsoletePagesDeleted)

        // 4. Projection last.
        try afterSave { try writeProjection(documents) }
        try step(.projectionWritten)
    }

    /// Runs a step that comes after index.enc is written. A failure is left for the next
    /// open() to repair, except a stop from the tests' crash hook, which must still stop.
    func afterSave(_ body: () throws -> Void) throws {
        let stopsBefore = crashHookStops
        do {
            try body()
        } catch {
            if crashHookStops != stopsBefore { throw error }
        }
    }

    private func writeIndex(_ documents: [IndexEntry]) throws {
        var state = try requireState()
        let next = VaultIndex(generation: state.index.generation + 1, documents: documents)
        let sealed = try VaultCrypto.seal(
            VaultJSON.encoder.encode(next), with: state.indexKey,
            as: .index(state.header.vaultID))
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
        try createFolder(projectionURL.deletingLastPathComponent(), protection: .completeUntilFirstUserAuthentication)
        try write(
            VaultJSON.encoder.encode(projection), to: projectionURL,
            protection: .completeUntilFirstUserAuthentication)
    }

    /// Writes a temp file, sets its class, then renames it over `url`, which keeps the class.
    /// If any step fails, `url` is left as it was.
    func write(_ data: Data, to url: URL, protection: FileProtectionClass) throws {
        let temp = Self.tempURL(for: url)
        do {
            try data.write(to: temp)
            try fileProtector.protect(temp, as: protection)
            guard rename(temp.path, url.path) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        } catch {
            try? FileManager.default.removeItem(at: temp)
            throw Self.isOutOfSpace(error) ? VaultError.storageFull : error
        }
    }

    /// Foundation reports a full disk as CocoaError 640 with ENOSPC underneath; rename gives ENOSPC.
    static func isOutOfSpace(_ error: any Error) -> Bool {
        let error = error as NSError
        let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError
        return (error.domain == NSCocoaErrorDomain && error.code == CocoaError.fileWriteOutOfSpace.rawValue)
            || [error, underlying].contains { $0?.domain == NSPOSIXErrorDomain && $0?.code == Int(ENOSPC) }
    }

    static func tempURL(for url: URL) -> URL {
        url.deletingLastPathComponent().appending(path: ".\(url.lastPathComponent).tmp")
    }

    /// A crash before the rename leaves a temp file. It was never part of a save, so it can go.
    func removeLeftoverTempFiles() throws {
        let fileManager = FileManager.default
        var leftovers = [Self.tempURL(for: projectionURL)]
        for directory in [root, pagesDirectory] where fileManager.fileExists(atPath: directory.path) {
            leftovers += try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                .filter { $0.lastPathComponent.hasPrefix(".") && $0.pathExtension == "tmp" }
        }
        for url in leftovers where fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    private func step(_ step: WriteStep) throws {
        do {
            try crashHook?(step)
        } catch {
            crashHookStops += 1
            throw error
        }
    }
}
