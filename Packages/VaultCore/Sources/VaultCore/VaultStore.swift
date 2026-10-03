import Crypto
import Foundation

/// Where the index came from when the vault was opened.
public enum IndexSource: Sendable, Equatable {
    /// A new vault was created.
    case new
    /// index.enc opened normally.
    case current
    /// index.enc was missing, unreadable or older than index.prev.enc; index.prev.enc was used.
    case previous
    /// Neither index file was usable; documents were rebuilt from page headers. Fields are lost.
    case recovered
}

/// What `open()` did. Holds only counts, never ids or contents, so the app may log it.
public struct OpenReport: Sendable, Equatable {
    public var createdVault = false
    public var indexSource = IndexSource.current
    public var purgedDocuments = 0
    public var removedOrphanPages = 0
    /// Page files that could not be opened. They are never deleted.
    public var unreadablePages = 0
}

/// A step of the write order, reported to the crash-simulation hook in tests.
enum WriteStep: Sendable, Equatable {
    case pagesWritten, indexMovedToPrevious, indexWritten, obsoletePagesDeleted, projectionWritten
}

/// The encrypted document store. Owns vault.json, the index files, the page files and the
/// projection, and follows the write order in the design doc for every change:
/// 1. new page files, 2. index.enc -> index.prev.enc then the new index.enc,
/// 3. delete page files the index no longer references, 4. projection.json.
public actor VaultStore {
    /// Documents in Recently deleted are purged this long after `deletedAt`.
    public static let purgeDelay: TimeInterval = 30 * 86_400
    /// Unreferenced page files younger than this are left alone.
    public static let orphanMinimumAge: TimeInterval = 5 * 60

    private let root: URL
    private let projectionURL: URL
    private let keyStore: any KeyStore
    private let clock: any Clock
    private let fileProtector: any FileProtector
    private let reminderOffsets: [Int]
    private let crashHook: (@Sendable (WriteStep) throws -> Void)?

    private struct OpenState {
        let header: VaultHeader
        let indexKey: SymmetricKey
        let wrapKey: SymmetricKey
        var index: VaultIndex
        /// True when index.enc on disk holds `index`. Only then may it become index.prev.enc.
        var indexFileIsCurrent: Bool
    }

    private var state: OpenState?
    private var lastReport: OpenReport?
    private var openTask: Task<OpenReport, any Error>?

    /// - Parameters:
    ///   - rootDirectory: the vault folder (Application Support/Vault in the app).
    ///   - projectionURL: projection.json (in the App Group container in the app).
    ///   - reminderOffsets: days before expiry written into the projection.
    public init(rootDirectory: URL, projectionURL: URL, keyStore: any KeyStore, clock: any Clock = SystemClock(),
                fileProtector: any FileProtector = NoFileProtection(), reminderOffsets: [Int] = [60, 30, 7]) {
        self.init(rootDirectory: rootDirectory, projectionURL: projectionURL, keyStore: keyStore, clock: clock,
                  fileProtector: fileProtector, reminderOffsets: reminderOffsets, crashHook: nil)
    }

    init(rootDirectory: URL, projectionURL: URL, keyStore: any KeyStore, clock: any Clock,
         fileProtector: any FileProtector = NoFileProtection(), reminderOffsets: [Int] = [60, 30, 7],
         crashHook: (@Sendable (WriteStep) throws -> Void)?) {
        root = rootDirectory
        self.projectionURL = projectionURL
        self.keyStore = keyStore
        self.clock = clock
        self.fileProtector = fileProtector
        self.reminderOffsets = reminderOffsets
        self.crashHook = crashHook
    }

    // MARK: - Paths

    private var headerURL: URL { root.appending(path: "vault.json") }
    private var indexURL: URL { root.appending(path: "index.enc") }
    private var previousIndexURL: URL { root.appending(path: "index.prev.enc") }
    private var pagesDirectory: URL { root.appending(path: "pages", directoryHint: .isDirectory) }
    private func pageURL(_ id: PageID) -> URL { pagesDirectory.appending(path: "\(id.string).enc") }

    // MARK: - Open and lock

    /// Unlocks the vault: reads the vault key, opens the index (falling back to
    /// index.prev.enc, then to recovery from page headers), removes orphaned pages,
    /// purges documents deleted 30 or more days ago and rewrites the projection.
    /// Creates a new vault only when there is no vault.json and no vault file at all.
    @discardableResult
    public func open() async throws -> OpenReport {
        if let openTask { return try await openTask.value }
        let task = Task { try await self.performOpen() }
        openTask = task
        defer { openTask = nil }
        return try await task.value
    }

    /// Drops every key and the decrypted index from memory.
    public func lock() {
        state = nil
        lastReport = nil
    }

    private func performOpen() async throws -> OpenReport {
        if state != nil, let lastReport { return lastReport }
        var report = OpenReport()
        let fm = FileManager.default

        let header: VaultHeader
        let vaultKey: SymmetricKey
        if fm.fileExists(atPath: headerURL.path) {
            header = try readHeader()
            vaultKey = try await readExistingVaultKey(header.vaultId)
        } else {
            guard try !vaultFilesExist() else { throw VaultError.vaultHeaderMissing }
            let vaultID = VaultID()
            vaultKey = try await readOrCreateNewVaultKey(vaultID)
            header = VaultHeader(vaultId: vaultID, keySlots: [KeySlot(kind: .device, createdAt: now())])
            try fm.createDirectory(at: pagesDirectory, withIntermediateDirectories: true)
            try write(VaultJSON.encoder.encode(header), to: headerURL, protection: .complete)
            report.createdVault = true
        }
        guard vaultKey.bitCount == 256 else { throw VaultError.vaultUnreadable }
        try fm.createDirectory(at: pagesDirectory, withIntermediateDirectories: true)

        let indexKey = VaultCrypto.indexKey(from: vaultKey, vaultID: header.vaultId)
        let wrapKey = VaultCrypto.wrapKey(from: vaultKey, vaultID: header.vaultId)
        let loaded = try loadIndex(vaultID: header.vaultId, indexKey: indexKey, wrapKey: wrapKey)
        report.indexSource = report.createdVault ? .new : loaded.source
        report.unreadablePages = loaded.unreadablePages
        state = OpenState(header: header, indexKey: indexKey, wrapKey: wrapKey, index: loaded.index,
                          indexFileIsCurrent: loaded.source == .current)

        do {
            if loaded.source != .current || loaded.previousHoldsRemovedDocuments {
                // Replace a missing, bad or stale index.enc, or finish an interrupted purge
                // so index.prev.enc no longer holds a purged document's sealed key.
                try commit(loaded.index.documents)
            }
            if loaded.allowsOrphanCleanup {
                report.removedOrphanPages = try removeOrphanPages(unreadable: &report.unreadablePages)
            }
            report.purgedDocuments = try purgeExpired()
            try writeProjection(try requireState().index.documents)
        } catch {
            state = nil
            throw error
        }
        lastReport = report
        return report
    }

    // MARK: - Reading

    /// Live documents, in the order they were added.
    public func documents() throws -> [Document] {
        try requireState().index.documents.filter { $0.deletedAt == nil }.map(\.document)
    }

    /// Documents in Recently deleted.
    public func recentlyDeleted() throws -> [Document] {
        try requireState().index.documents.filter { $0.deletedAt != nil }.map(\.document)
    }

    public func document(_ id: DocumentID) throws -> Document {
        try entry(id).document
    }

    public func fields(of id: DocumentID) throws -> DocumentFields {
        let entry = try entry(id)
        let key = try documentKey(entry)
        let plain = try VaultCrypto.open(entry.sealedFields, with: key, as: .fields(id))
        do {
            return try VaultJSON.decoder.decode(DocumentFields.self, from: plain)
        } catch {
            throw VaultError.corruptFile
        }
    }

    public func pages(of id: DocumentID) throws -> [Page] {
        try entry(id).pageIds.map { try page($0, of: id) }
    }

    /// Decrypts one page. The page file must name this document and page in its header and
    /// open with this document's key and "page|v1|<docId>|<pageId>".
    public func page(_ pageID: PageID, of id: DocumentID) throws -> Page {
        let entry = try entry(id)
        guard entry.pageIds.contains(pageID) else { throw VaultError.pageNotFound }
        let raw: Data
        do {
            raw = try Data(contentsOf: pageURL(pageID))
        } catch {
            throw VaultError.pageNotFound
        }
        let file = try PageFile(decoding: raw)
        guard file.header.formatVersion <= PageHeader.currentFormatVersion else { throw VaultError.unsupportedVersion }
        guard file.header.docId == id, file.header.pageId == pageID, file.header.sealedKey == entry.sealedKey else {
            throw VaultError.authenticationFailed
        }
        let key = try documentKey(entry)
        let data = try VaultCrypto.open(file.sealedContent, with: key, as: .page(id, pageID))
        return Page(id: pageID, data: data)
    }

    // MARK: - Changes

    /// Creates a document with a new random key. Each page is sealed straight from memory.
    public func createDocument(type: DocumentType, expiry: CalendarDate?, pinned: Bool,
                               fields: DocumentFields, pages: [Data]) throws -> DocumentID {
        let state = try requireState()
        let id = DocumentID()
        let key = VaultCrypto.newKey()
        let sealedKey = try VaultCrypto.sealDocumentKey(key, with: state.wrapKey, documentID: id)
        var newPages: [(PageID, Data)] = []
        for data in pages {
            let pageID = PageID()
            newPages.append((pageID, try pageFile(data, pageID: pageID, documentID: id, key: key, sealedKey: sealedKey)))
        }
        let stamp = now()
        let entry = IndexEntry(id: id, type: type, createdAt: stamp, updatedAt: stamp, expiry: expiry,
                               pinned: pinned, deletedAt: nil, sealedKey: sealedKey,
                               sealedFields: try sealFields(fields, key: key, documentID: id),
                               pageIds: newPages.map(\.0))
        try commit(state.index.documents + [entry], newPages: newPages)
        return id
    }

    /// Replaces type, expiry, pinned and fields. Fields are resealed with the same document
    /// key and a fresh nonce.
    public func editDocument(_ id: DocumentID, type: DocumentType, expiry: CalendarDate?, pinned: Bool,
                             fields: DocumentFields) throws {
        try update(id) { entry, key in
            entry.type = type
            entry.expiry = expiry
            entry.pinned = pinned
            entry.sealedFields = try self.sealFields(fields, key: key, documentID: id)
            entry.updatedAt = self.now()
            return ([], [])
        }
    }

    /// Appends a page to the end of the document.
    public func addPage(_ data: Data, to id: DocumentID) throws -> PageID {
        let pageID = PageID()
        try update(id) { entry, key in
            let file = try self.pageFile(data, pageID: pageID, documentID: id, key: key, sealedKey: entry.sealedKey)
            entry.pageIds.append(pageID)
            entry.updatedAt = self.now()
            return ([(pageID, file)], [])
        }
        return pageID
    }

    /// Writes the new page, points the document at it, then deletes the old page file.
    public func replacePage(_ pageID: PageID, of id: DocumentID, with data: Data) throws -> PageID {
        let newID = PageID()
        try update(id) { entry, key in
            guard let position = entry.pageIds.firstIndex(of: pageID) else { throw VaultError.pageNotFound }
            let file = try self.pageFile(data, pageID: newID, documentID: id, key: key, sealedKey: entry.sealedKey)
            entry.pageIds[position] = newID
            entry.updatedAt = self.now()
            return ([(newID, file)], [pageID])
        }
        return newID
    }

    /// Moves the document to Recently deleted. Keys and files stay until the purge.
    public func delete(_ id: DocumentID) throws {
        try update(id) { entry, _ in
            entry.deletedAt = self.now()
            return ([], [])
        }
    }

    /// Brings a document back from Recently deleted.
    public func restore(_ id: DocumentID) throws {
        try update(id) { entry, _ in
            entry.deletedAt = nil
            return ([], [])
        }
    }

    /// Purges a document now, whether or not it is in Recently deleted. The app confirms first.
    public func deletePermanently(_ id: DocumentID) throws {
        let entry = try entry(id)
        try purge([entry])
    }

    /// Purges documents deleted `purgeDelay` or longer ago. Returns how many were purged.
    @discardableResult
    public func purgeExpired() throws -> Int {
        let now = now()
        let expired = try requireState().index.documents.filter { entry in
            guard let deletedAt = entry.deletedAt else { return false }
            return now >= deletedAt + Self.purgeDelay
        }
        guard !expired.isEmpty else { return 0 }
        try purge(expired)
        return expired.count
    }

    /// Removes the entries and writes the index twice, so index.prev.enc no longer holds
    /// their sealed keys either; then deletes their page files.
    private func purge(_ entries: [IndexEntry]) throws {
        let ids = Set(entries.map(\.id))
        let remaining = try requireState().index.documents.filter { !ids.contains($0.id) }
        try commit(remaining, obsoletePages: entries.flatMap(\.pageIds), writeIndexTwice: true)
    }

    private func update(
        _ id: DocumentID,
        _ change: (inout IndexEntry, SymmetricKey) throws -> (newPages: [(PageID, Data)], obsoletePages: [PageID])
    ) throws {
        var documents = try requireState().index.documents
        guard let position = documents.firstIndex(where: { $0.id == id }) else { throw VaultError.documentNotFound }
        let key = try documentKey(documents[position])
        let (newPages, obsoletePages) = try change(&documents[position], key)
        try commit(documents, newPages: newPages, obsoletePages: obsoletePages)
    }

    // MARK: - The write order

    private func commit(_ documents: [IndexEntry], newPages: [(PageID, Data)] = [],
                        obsoletePages: [PageID] = [], writeIndexTwice: Bool = false) throws {
        // 1. New page files.
        for (pageID, data) in newPages {
            try write(data, to: pageURL(pageID), protection: .complete)
        }
        try step(.pagesWritten)

        // 2. Rotate and write the index (twice for a purge).
        try writeIndex(documents)
        if writeIndexTwice { try writeIndex(documents) }

        // 3. Page files the index no longer references.
        let fm = FileManager.default
        for pageID in obsoletePages where fm.fileExists(atPath: pageURL(pageID).path) {
            try fm.removeItem(at: pageURL(pageID))
        }
        try step(.obsoletePagesDeleted)

        // 4. Projection last.
        try writeProjection(documents)
        try step(.projectionWritten)
    }

    private func writeIndex(_ documents: [IndexEntry]) throws {
        var state = try requireState()
        let next = VaultIndex(generation: state.index.generation + 1, documents: documents)
        let sealed = try VaultCrypto.seal(VaultJSON.encoder.encode(next), with: state.indexKey,
                                          as: .index(state.header.vaultId))
        let fm = FileManager.default
        if state.indexFileIsCurrent, fm.fileExists(atPath: indexURL.path) {
            if fm.fileExists(atPath: previousIndexURL.path) { try fm.removeItem(at: previousIndexURL) }
            try fm.moveItem(at: indexURL, to: previousIndexURL)
        }
        try step(.indexMovedToPrevious)
        try write(sealed, to: indexURL, protection: .complete)
        state.index = next
        state.indexFileIsCurrent = true
        self.state = state
        try step(.indexWritten)
    }

    private func writeProjection(_ documents: [IndexEntry]) throws {
        let projection = Projection(documents: documents.filter { $0.deletedAt == nil }.map {
            ProjectionEntry(id: $0.id, type: $0.type, expiry: $0.expiry, reminderOffsets: reminderOffsets)
        })
        try FileManager.default.createDirectory(at: projectionURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try write(VaultJSON.encoder.encode(projection), to: projectionURL,
                  protection: .completeUntilFirstUserAuthentication)
    }

    private func write(_ data: Data, to url: URL, protection: FileProtectionClass) throws {
        try data.write(to: url, options: .atomic)
        try fileProtector.protect(url, as: protection)
    }

    private func step(_ step: WriteStep) throws {
        try crashHook?(step)
    }

    // MARK: - Loading the index

    private enum IndexFile {
        case missing, unreadable
        case readable(VaultIndex)

        var isMissing: Bool {
            if case .missing = self { true } else { false }
        }
    }

    private struct LoadedIndex {
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

    private func loadIndex(vaultID: VaultID, indexKey: SymmetricKey, wrapKey: SymmetricKey) throws -> LoadedIndex {
        let current = try readIndexFile(indexURL, vaultID: vaultID, indexKey: indexKey)
        let previous = try readIndexFile(previousIndexURL, vaultID: vaultID, indexKey: indexKey)

        switch (current, previous) {
        case (.readable(let cur), .readable(let prev)) where cur.generation > prev.generation:
            let removed = !Set(prev.documents.map(\.id)).isSubset(of: cur.documents.map(\.id))
            return LoadedIndex(index: cur, source: .current, previousHoldsRemovedDocuments: removed,
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
            loaded.index.documents = try reattachPages(to: prev.documents, wrapKey: wrapKey,
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
        let fm = FileManager.default
        guard fm.fileExists(atPath: pagesDirectory.path) else { return [] }
        let urls = try fm.contentsOfDirectory(at: pagesDirectory, includingPropertiesForKeys: [.contentModificationDateKey])
        return urls.compactMap { url in
            guard url.pathExtension == "enc",
                  let id = PageID(string: url.deletingPathExtension().lastPathComponent) else { return nil }
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
              let key = try? VaultCrypto.openDocumentKey(file.header.sealedKey, with: wrapKey,
                                                         documentID: file.header.docId),
              (try? VaultCrypto.open(file.sealedContent, with: key, as: .page(file.header.docId, info.id))) != nil
        else { return nil }
        return file.header
    }

    /// Adds every intact page file that `documents` does not reference: to its document if
    /// it exists, else to a new "other" document with empty fields. Drops references to
    /// page files that no longer exist.
    private func reattachPages(to documents: [IndexEntry], wrapKey: SymmetricKey,
                               unreadable: inout Int) throws -> [IndexEntry] {
        let files = try listPageFiles().sorted { ($0.modified, $0.id.string) < ($1.modified, $1.id.string) }
        let existing = Set(files.map(\.id))
        var result = documents.map { entry in
            var entry = entry
            entry.pageIds = entry.pageIds.filter(existing.contains)
            return entry
        }
        let referenced = Set(result.flatMap(\.pageIds))
        let stamp = now()
        for info in files where !referenced.contains(info.id) {
            guard let header = verifiedHeader(info, wrapKey: wrapKey) else {
                unreadable += 1
                continue
            }
            if let position = result.firstIndex(where: { $0.id == header.docId }) {
                result[position].pageIds.append(info.id)
            } else {
                let key = try VaultCrypto.openDocumentKey(header.sealedKey, with: wrapKey, documentID: header.docId)
                result.append(IndexEntry(
                    id: header.docId, type: .other, createdAt: stamp, updatedAt: stamp, expiry: nil, pinned: false,
                    deletedAt: nil, sealedKey: header.sealedKey,
                    sealedFields: try sealFields(DocumentFields(), key: key, documentID: header.docId),
                    pageIds: [info.id]))
            }
        }
        return result
    }

    /// Deletes page files that no index entry references, that are older than
    /// `orphanMinimumAge`, and that open with this vault's key. Unreadable files are kept.
    private func removeOrphanPages(unreadable: inout Int) throws -> Int {
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

    private func vaultFilesExist() throws -> Bool {
        let fm = FileManager.default
        if fm.fileExists(atPath: indexURL.path) || fm.fileExists(atPath: previousIndexURL.path) { return true }
        return try !listPageFiles().isEmpty
    }

    // MARK: - Keys

    private func readHeader() throws -> VaultHeader {
        struct VersionProbe: Decodable { var formatVersion: Int }
        guard let data = try? Data(contentsOf: headerURL),
              let probe = try? VaultJSON.decoder.decode(VersionProbe.self, from: data) else {
            throw VaultError.corruptFile
        }
        guard probe.formatVersion <= VaultHeader.currentFormatVersion else { throw VaultError.unsupportedVersion }
        guard let header = try? VaultJSON.decoder.decode(VaultHeader.self, from: data) else {
            throw VaultError.corruptFile
        }
        return header
    }

    /// The vault exists, so its key must too. Not found means the key is gone; anything
    /// else means it is there but locked. Neither ever leads to a new key.
    private func readExistingVaultKey(_ vaultID: VaultID) async throws -> SymmetricKey {
        do {
            return try await keyStore.readVaultKey(for: vaultID)
        } catch KeyStoreError.itemNotFound {
            throw VaultError.vaultKeyMissing
        } catch {
            throw VaultError.vaultKeyUnavailable
        }
    }

    /// For a new vault: create a key only when the key store reports it does not exist.
    private func readOrCreateNewVaultKey(_ vaultID: VaultID) async throws -> SymmetricKey {
        do {
            return try await keyStore.readVaultKey(for: vaultID)
        } catch KeyStoreError.itemNotFound {
            do {
                return try await keyStore.createVaultKey(for: vaultID)
            } catch {
                throw VaultError.vaultKeyUnavailable
            }
        } catch {
            throw VaultError.vaultKeyUnavailable
        }
    }

    private func documentKey(_ entry: IndexEntry) throws -> SymmetricKey {
        try VaultCrypto.openDocumentKey(entry.sealedKey, with: requireState().wrapKey, documentID: entry.id)
    }

    // MARK: - Helpers

    private func requireState() throws -> OpenState {
        guard let state else { throw VaultError.locked }
        return state
    }

    private func entry(_ id: DocumentID) throws -> IndexEntry {
        guard let entry = try requireState().index.documents.first(where: { $0.id == id }) else {
            throw VaultError.documentNotFound
        }
        return entry
    }

    /// Timestamps are whole seconds so they survive the ISO 8601 round trip exactly.
    private func now() -> Date {
        Date(timeIntervalSince1970: clock.now.timeIntervalSince1970.rounded(.down))
    }

    private func sealFields(_ fields: DocumentFields, key: SymmetricKey, documentID: DocumentID) throws -> Data {
        try VaultCrypto.seal(VaultJSON.encoder.encode(fields), with: key, as: .fields(documentID))
    }

    private func pageFile(_ data: Data, pageID: PageID, documentID: DocumentID, key: SymmetricKey,
                          sealedKey: Data) throws -> Data {
        let sealed = try VaultCrypto.seal(data, with: key, as: .page(documentID, pageID))
        return try PageFile(header: PageHeader(docId: documentID, pageId: pageID, sealedKey: sealedKey),
                            sealedContent: sealed).encoded()
    }
}

