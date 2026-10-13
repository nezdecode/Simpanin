//
//  VaultStore+Recovery.swift
//  VaultCore
//
//  Created by Inez Amanda on 10/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Crypto
import Foundation

extension VaultStore {
    // MARK: - Loading the index

    private enum IndexFile {
        case missing, unreadable
        case readable(VaultIndex)

        var isMissing: Bool {
            if case .missing = self { true } else { false }
        }
    }

    struct LoadedIndex {
        var index: VaultIndex
        var source: IndexSource
        var unreadablePages = 0
        /// index.prev.enc still lists documents that index.enc dropped, after an interrupted purge.
        var previousHoldsRemovedDocuments = false
        /// Unreferenced pages are leftovers from changes that never committed, so they can go.
        var allowsOrphanCleanup = false
    }

    private func readIndexFile(_ url: URL, vaultID: VaultID, indexKey: SymmetricKey) throws -> IndexFile {
        guard let sealed = try readFile(at: url) else { return .missing }
        guard let plain = try? VaultCrypto.open(sealed, with: indexKey, as: .index(vaultID)) else { return .unreadable }
        struct VersionProbe: Decodable { var schemaVersion: Int }
        guard let probe = try? VaultJSON.decoder.decode(VersionProbe.self, from: plain) else { return .unreadable }
        // A newer build wrote this vault. Stop, rather than fall back and overwrite it.
        guard probe.schemaVersion <= VaultIndex.currentSchemaVersion else { throw VaultError.unsupportedVersion }
        guard let index = try? VaultJSON.decoder.decode(VaultIndex.self, from: plain) else { return .unreadable }
        return .readable(index)
    }

    func loadIndex(vaultID: VaultID, indexKey: SymmetricKey, wrapKey: SymmetricKey) throws -> LoadedIndex {
        let current = try readIndexFile(indexURL, vaultID: vaultID, indexKey: indexKey)
        let previous = try readIndexFile(previousIndexURL, vaultID: vaultID, indexKey: indexKey)

        switch (current, previous) {
        case (.readable(let cur), .readable(let prev)) where cur.generation > prev.generation:
            let removed = !Set(prev.documents.map(\.id)).isSubset(of: cur.documents.map(\.id))
            return LoadedIndex(
                index: cur, source: .current, previousHoldsRemovedDocuments: removed,
                allowsOrphanCleanup: true)
        case (.readable(let cur), .missing), (.readable(let cur), .unreadable):
            return LoadedIndex(index: cur, source: .current, allowsOrphanCleanup: true)
        case (.missing, .readable(let prev)):
            // A crash between the two index writes: the newer change never committed.
            return LoadedIndex(index: prev, source: .previous, allowsOrphanCleanup: true)
        case (_, .readable(let prev)):
            // index.enc is bad or stale, but its pages may be committed, so keep them.
            var loaded = LoadedIndex(index: prev, source: .previous)
            loaded.index.documents = try reattachPages(
                to: prev.documents, wrapKey: wrapKey,
                unreadable: &loaded.unreadablePages)
            return loaded
        default:
            let indexFilesExist = !(current.isMissing && previous.isMissing)
            var loaded = LoadedIndex(index: VaultIndex(generation: 0, documents: []), source: .recovered)
            loaded.index.documents = try reattachPages(to: [], wrapKey: wrapKey, unreadable: &loaded.unreadablePages)
            let recoveredPages = loaded.index.documents.reduce(0) { $0 + $1.pageIDs.count }
            if recoveredPages == 0, indexFilesExist || loaded.unreadablePages > 0 {
                // Nothing opens with this key, which most likely means it's the wrong one.
                // Change nothing.
                throw VaultError.vaultUnreadable
            }
            return loaded
        }
    }

    // MARK: - Page files on disk

    private struct PageFileInfo {
        let url: URL
        let id: PageID
        let modified: Date
    }

    private func listPageFiles() throws -> [PageFileInfo] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: pagesDirectory.path) else { return [] }
        let urls = try fileManager.contentsOfDirectory(
            at: pagesDirectory, includingPropertiesForKeys: [.contentModificationDateKey])
        return urls.compactMap { url in
            guard url.pathExtension == "enc",
                let id = PageID(string: url.deletingPathExtension().lastPathComponent)
            else { return nil }
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            return PageFileInfo(url: url, id: id, modified: modified ?? .distantPast)
        }
    }

    /// The page's header if it opens with this vault's key, else nil.
    private func verifiedHeader(_ info: PageFileInfo, wrapKey: SymmetricKey) throws -> PageHeader? {
        guard let data = try readFile(at: info.url),
            let file = try? PageFile(decoding: data),
            file.header.formatVersion == PageHeader.currentFormatVersion,
            file.header.pageID == info.id,
            let key = try? VaultCrypto.openDocumentKey(
                file.header.sealedKey, with: wrapKey,
                documentID: file.header.documentID),
            (try? VaultCrypto.open(file.sealedContent, with: key, as: .page(file.header.documentID, info.id))) != nil
        else { return nil }
        return file.header
    }

    /// Adds intact unreferenced pages to their document, or to a new "other" document if it
    /// is gone. Drops references to missing files.
    private func reattachPages(
        to documents: [IndexEntry], wrapKey: SymmetricKey,
        unreadable: inout Int
    ) throws -> [IndexEntry] {
        let files = try listPageFiles().sorted { ($0.modified, $0.id.string) < ($1.modified, $1.id.string) }
        let existing = Set(files.map(\.id))
        var result = documents.map { entry in
            var entry = entry
            entry.pageIDs = entry.pageIDs.filter(existing.contains)
            return entry
        }
        let referenced = Set(result.flatMap(\.pageIDs))
        let stamp = now()
        var positions: [PageID: Int] = [:]
        var touched: Set<DocumentID> = []
        for info in files where !referenced.contains(info.id) {
            guard let header = try verifiedHeader(info, wrapKey: wrapKey) else {
                unreadable += 1
                continue
            }
            positions[info.id] = header.position
            touched.insert(header.documentID)
            if let position = result.firstIndex(where: { $0.id == header.documentID }) {
                result[position].pageIDs.append(info.id)
            } else {
                let key = try VaultCrypto.openDocumentKey(
                    header.sealedKey, with: wrapKey, documentID: header.documentID)
                result.append(
                    IndexEntry(
                        id: header.documentID, type: .other, createdAt: stamp, updatedAt: stamp, expiry: nil,
                        pinned: false,
                        deletedAt: nil, sealedKey: header.sealedKey,
                        sealedFields: try sealFields(DocumentFields(), key: key, documentID: header.documentID),
                        pageIDs: [info.id]))
            }
        }
        // Restore page order from the header positions. Ties keep file-time order.
        for index in result.indices where touched.contains(result[index].id) {
            let ordered = result[index].pageIDs.enumerated().map { offset, pageID in
                (pageID, positions[pageID] ?? storedPosition(of: pageID) ?? Int.max, offset)
            }
            result[index].pageIDs = ordered.sorted { ($0.1, $0.2) < ($1.1, $1.2) }.map(\.0)
        }
        return result
    }

    /// Reads the position from the plaintext header, without decrypting.
    private func storedPosition(of pageID: PageID) -> Int? {
        guard let data = try? Data(contentsOf: pageURL(pageID)) else { return nil }
        return (try? PageFile(decoding: data))?.header.position
    }

    /// Deletes unreferenced pages older than `orphanMinimumAge` that open with this vault's
    /// key. Unreadable files are always kept.
    func removeOrphanPages(unreadable: inout Int) throws -> Int {
        let state = try requireState()
        let referenced = Set(state.index.documents.flatMap(\.pageIDs))
        let now = clock.now
        var removed = 0
        for info in try listPageFiles() where !referenced.contains(info.id) {
            guard try verifiedHeader(info, wrapKey: state.wrapKey) != nil else {
                unreadable += 1
                continue
            }
            guard now.timeIntervalSince(info.modified) >= Self.orphanMinimumAge else { continue }
            try FileManager.default.removeItem(at: info.url)
            removed += 1
        }
        return removed
    }

    func vaultFilesExist() throws -> Bool {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: indexURL.path) || fileManager.fileExists(atPath: previousIndexURL.path) {
            return true
        }
        return try !listPageFiles().isEmpty
    }
}
