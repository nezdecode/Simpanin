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
        // 1. New page files, flushed with their folder, so no index names a page that isn't on
        //    disk. A failure here fails the save, and a later open removes the pages.
        var methods: [FlushMethod] = []
        for (pageID, data) in newPages {
            try write(data, to: pageURL(pageID), protection: .complete)
            methods.append(try flusher.flush(pageURL(pageID)))
        }
        if !newPages.isEmpty { methods.append(try flusher.flush(pagesDirectory)) }
        try step(.pagesWritten)

        // 2. Rotate, write and flush the index. Once index.enc is written the change is saved.
        //    Anything that fails after this is repaired by the next open().
        let flushed = try writeIndex(documents, flushMethods: &methods)

        // 3. Delete pages the index no longer references, only once it's on disk. If its flush
        //    failed, they stay until orphan cleanup on a later open. A purge flushes the pages
        //    folder and writes the index again after its pages are gone, so index.prev.enc loses
        //    the purged keys and nothing is left to bring them back.
        var allFlushed = flushed
        if flushed {
            allFlushed = try deleteObsoletePages(obsoletePages, flushingFolder: writeIndexTwice, flushMethods: &methods)
        }
        try step(.obsoletePagesDeleted)
        if writeIndexTwice {
            var flushedAgain = false
            try afterSave { flushedAgain = try writeIndex(documents, flushMethods: &methods) }
            if flushedAgain, !flushed {
                // The first write never reached the disk, so the pages waited for this one.
                _ = try deleteObsoletePages(obsoletePages, flushingFolder: true, flushMethods: &methods)
            }
            allFlushed = allFlushed && flushedAgain
        }
        // A commit is only as durable as its weakest flush.
        if allFlushed { lastFlushMethod = methods.allSatisfy { $0 == .fullFsync } ? .fullFsync : .fsync }

        // 4. Projection last.
        try afterSave { try writeProjection(documents) }
        try step(.projectionWritten)
    }

    /// Deletes the page files in `pageIDs` that still exist. With `flushingFolder`, it then flushes
    /// the pages folder, so the deletions reach the disk; returns whether that flush worked.
    private func deleteObsoletePages(
        _ pageIDs: [PageID], flushingFolder: Bool, flushMethods: inout [FlushMethod]
    ) throws -> Bool {
        var deleted = false
        for pageID in pageIDs where FileManager.default.fileExists(atPath: pageURL(pageID).path) {
            try afterSave { try FileManager.default.removeItem(at: pageURL(pageID)) }
            deleted = true
        }
        guard flushingFolder, deleted else { return true }
        do {
            flushMethods.append(try flusher.flush(pagesDirectory))
            return true
        } catch {
            return false
        }
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

    /// Writes the index, then flushes it and the vault folder, adding their methods to
    /// `flushMethods`. Returns whether both flushes worked. Only an index that reached the disk is
    /// ever moved to index.prev.enc, so one whose flush failed is replaced by the next write.
    private func writeIndex(_ documents: [IndexEntry], flushMethods: inout [FlushMethod]) throws -> Bool {
        var state = try requireState()
        let next = VaultIndex(generation: state.index.generation + 1, documents: documents)
        let sealed = try VaultCrypto.seal(
            VaultJSON.encoder.encode(next), with: state.indexKey,
            as: .index(state.header.vaultID))
        let fileManager = FileManager.default
        if state.indexFileIsOnDisk, fileManager.fileExists(atPath: indexURL.path) {
            if fileManager.fileExists(atPath: previousIndexURL.path) {
                try fileManager.removeItem(at: previousIndexURL)
            }
            try fileManager.moveItem(at: indexURL, to: previousIndexURL)
        }
        try step(.indexMovedToPrevious)
        try write(sealed, to: indexURL, protection: .complete)
        state.index = next
        state.indexFileIsOnDisk = false
        self.state = state
        try step(.indexWritten)
        do {
            flushMethods += [try flusher.flush(indexURL), try flusher.flush(root)]
        } catch {
            return false
        }
        self.state?.indexFileIsOnDisk = true
        return true
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
        try writeThroughTemp(data, to: url, protection: protection) { temp in
            guard rename(temp.path, url.path) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        }
    }

    /// Like `write`, for a file that must not exist yet. Linking the temp into place fails rather
    /// than replace a file that appeared meanwhile, and that throws `fileUnavailable`. Only a new
    /// vault's header uses it, so a wrong "no vault" can never put a new vault over an old one.
    func writeNew(_ data: Data, to url: URL, protection: FileProtectionClass) throws {
        try writeThroughTemp(data, to: url, protection: protection) { temp in
            guard link(temp.path, url.path) == 0 else {
                let code = errno
                throw code == EEXIST ? VaultError.fileUnavailable : POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
            }
        }
        // The temp name stays as a second name until an open removes leftovers, usually this one;
        // `write` never writes through it.
    }

    /// Writes `data` to a fresh temp file beside `url`, sets its class, then lets `place` put it at
    /// `url`. On any failure the temp file is removed and `url` is left as it was.
    private func writeThroughTemp(
        _ data: Data, to url: URL, protection: FileProtectionClass, place: (_ temp: URL) throws -> Void
    ) throws {
        let temp = Self.tempURL(for: url)
        do {
            // Not optional cleanup: a leftover temp can be a hard link to `url` (from `writeNew`), and
            // writing through it would change `url` before it's placed.
            do {
                try FileManager.default.removeItem(at: temp)
            } catch CocoaError.fileNoSuchFile {
            }
            try data.write(to: temp)
            try fileProtector.protect(temp, as: protection)
            try place(temp)
        } catch {
            try? FileManager.default.removeItem(at: temp)
            throw Self.isOutOfSpace(error) ? VaultError.storageFull : error
        }
    }

    /// Foundation reports a full disk as CocoaError 640 with ENOSPC underneath; rename gives ENOSPC. Public, so
    /// the app's own writes (shared copies) call a full disk what the vault calls one.
    public static func isOutOfSpace(_ error: any Error) -> Bool {
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
