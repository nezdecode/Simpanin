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
        /// index.prev.enc still lists documents that index.enc dropped (an interrupted purge).
        var previousHoldsRemovedDocuments = false
        /// Unreferenced pages are uncommitted leftovers and may be deleted.
        var allowsOrphanCleanup = false
    }

    private func readIndexFile(_ url: URL, vaultID: VaultID, indexKey: SymmetricKey) throws -> IndexFile {
        guard let sealed = try? Data(contentsOf: url) else {
            return FileManager.default.fileExists(atPath: url.path) ? .unreadable : .missing
        }
        guard let plain = try? VaultCrypto.open(sealed, with: indexKey, as: .index(vaultID)) else { return .unreadable }
        struct VersionProbe: Decodable { var schemaVersion: Int }
        guard let probe = try? VaultJSON.decoder.decode(VersionProbe.self, from: plain) else { return .unreadable }
        // A newer build wrote this vault: stop rather than fall back and overwrite it.
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
            // A crash between moving index.enc and writing the new one: the newer change
            // was never committed, so its pages are leftovers.
            return LoadedIndex(index: prev, source: .previous, allowsOrphanCleanup: true)
        case (_, .readable(let prev)):
            // index.enc is unreadable or stale (older than index.prev.enc). Its newest
            // generation may have committed pages, so re-attach them instead of deleting.
            var loaded = LoadedIndex(index: prev, source: .previous)
            loaded.index.documents = try reattachPages(
                to: prev.documents, wrapKey: wrapKey,
                unreadable: &loaded.unreadablePages)
            return loaded
        default:
            let indexFilesExist = !(current.isMissing && previous.isMissing)
            var loaded = LoadedIndex(index: VaultIndex(generation: 0, documents: []), source: .recovered)
            loaded.index.documents = try reattachPages(to: [], wrapKey: wrapKey, unreadable: &loaded.unreadablePages)
            let recoveredPages = loaded.index.documents.reduce(0) { $0 + $1.pageIds.count }
            if recoveredPages == 0, indexFilesExist || loaded.unreadablePages > 0 {
                // Nothing opens with this key. Most likely the wrong key: change nothing.
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

    /// Opens a page file with only the vault's wrap key, using the sealed document key in
    /// its own header. Returns the header if the page is intact, nil otherwise.
    private func verifiedHeader(_ info: PageFileInfo, wrapKey: SymmetricKey) -> PageHeader? {
        guard let data = try? Data(contentsOf: info.url),
            let file = try? PageFile(decoding: data),
            file.header.formatVersion == PageHeader.currentFormatVersion,
            file.header.pageId == info.id,
            let key = try? VaultCrypto.openDocumentKey(
                file.header.sealedKey, with: wrapKey,
                documentID: file.header.docId),
            (try? VaultCrypto.open(file.sealedContent, with: key, as: .page(file.header.docId, info.id))) != nil
        else { return nil }
        return file.header
    }

    /// Adds every intact page file that `documents` does not reference: to its document if
    /// it exists, else to a new "other" document with empty fields. Drops references to
    /// page files that no longer exist.
    private func reattachPages(
        to documents: [IndexEntry], wrapKey: SymmetricKey,
        unreadable: inout Int
    ) throws -> [IndexEntry] {
        let files = try listPageFiles().sorted { ($0.modified, $0.id.string) < ($1.modified, $1.id.string) }
        let existing = Set(files.map(\.id))
        var result = documents.map { entry in
            var entry = entry
            entry.pageIds = entry.pageIds.filter(existing.contains)
            return entry
        }
        let referenced = Set(result.flatMap(\.pageIds))
        let stamp = now()
        var positions: [PageID: Int] = [:]
        var touched: Set<DocumentID> = []
        for info in files where !referenced.contains(info.id) {
            guard let header = verifiedHeader(info, wrapKey: wrapKey) else {
                unreadable += 1
                continue
            }
            positions[info.id] = header.position
            touched.insert(header.docId)
            if let position = result.firstIndex(where: { $0.id == header.docId }) {
                result[position].pageIds.append(info.id)
            } else {
                let key = try VaultCrypto.openDocumentKey(header.sealedKey, with: wrapKey, documentID: header.docId)
                result.append(
                    IndexEntry(
                        id: header.docId, type: .other, createdAt: stamp, updatedAt: stamp, expiry: nil, pinned: false,
                        deletedAt: nil, sealedKey: header.sealedKey,
                        sealedFields: try sealFields(DocumentFields(), key: key, documentID: header.docId),
                        pageIds: [info.id]))
            }
        }
        // Put every document that gained pages back in page order, using the position each
        // page header stores. Ties (a crash left two versions of a page) keep file-time order.
        for index in result.indices where touched.contains(result[index].id) {
            let ordered = result[index].pageIds.enumerated().map { offset, pageID in
                (pageID, positions[pageID] ?? storedPosition(of: pageID) ?? Int.max, offset)
            }
            result[index].pageIds = ordered.sorted { ($0.1, $0.2) < ($1.1, $1.2) }.map(\.0)
        }
        return result
    }

    /// The position in a page file's plaintext header, without decrypting the page.
    private func storedPosition(of pageID: PageID) -> Int? {
        guard let data = try? Data(contentsOf: pageURL(pageID)) else { return nil }
        return (try? PageFile(decoding: data))?.header.position
    }

    /// Deletes page files that no index entry references, that are older than
    /// `orphanMinimumAge`, and that open with this vault's key. Unreadable files are kept.
    func removeOrphanPages(unreadable: inout Int) throws -> Int {
        let state = try requireState()
        let referenced = Set(state.index.documents.flatMap(\.pageIds))
        let now = clock.now
        var removed = 0
        for info in try listPageFiles() where !referenced.contains(info.id) {
            guard verifiedHeader(info, wrapKey: state.wrapKey) != nil else {
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
