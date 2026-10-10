import Crypto
import Foundation

extension VaultStore {
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
    public func createDocument(
        type: DocumentType, expiry: CalendarDate?, pinned: Bool,
        fields: DocumentFields, pages: [Data]
    ) throws -> DocumentID {
        let state = try requireState()
        let id = DocumentID()
        let key = VaultCrypto.newKey()
        let sealedKey = try VaultCrypto.sealDocumentKey(key, with: state.wrapKey, documentID: id)
        var newPages: [(PageID, Data)] = []
        for (position, data) in pages.enumerated() {
            let pageID = PageID()
            let file = try pageFile(
                data, pageID: pageID, position: position, documentID: id, key: key, sealedKey: sealedKey)
            newPages.append((pageID, file))
        }
        let stamp = now()
        let entry = IndexEntry(
            id: id, type: type, createdAt: stamp, updatedAt: stamp, expiry: expiry,
            pinned: pinned, deletedAt: nil, sealedKey: sealedKey,
            sealedFields: try sealFields(fields, key: key, documentID: id),
            pageIds: newPages.map(\.0))
        try commit(state.index.documents + [entry], newPages: newPages)
        return id
    }

    /// Replaces type, expiry, pinned and fields. Fields are resealed with the same document
    /// key and a fresh nonce. Throws `documentDeleted` while the document is in Recently deleted.
    public func editDocument(
        _ id: DocumentID, type: DocumentType, expiry: CalendarDate?, pinned: Bool,
        fields: DocumentFields
    ) throws {
        try update(id, rejectDeleted: true) { entry, key in
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
        try update(id, rejectDeleted: true) { entry, key in
            let file = try self.pageFile(
                data, pageID: pageID, position: entry.pageIds.count, documentID: id,
                key: key, sealedKey: entry.sealedKey)
            entry.pageIds.append(pageID)
            entry.updatedAt = self.now()
            return ([(pageID, file)], [])
        }
        return pageID
    }

    /// Writes the new page, points the document at it, then deletes the old page file.
    public func replacePage(_ pageID: PageID, of id: DocumentID, with data: Data) throws -> PageID {
        let newID = PageID()
        try update(id, rejectDeleted: true) { entry, key in
            guard let position = entry.pageIds.firstIndex(of: pageID) else { throw VaultError.pageNotFound }
            let file = try self.pageFile(
                data, pageID: newID, position: position, documentID: id,
                key: key, sealedKey: entry.sealedKey)
            entry.pageIds[position] = newID
            entry.updatedAt = self.now()
            return ([(newID, file)], [pageID])
        }
        return newID
    }

    /// Moves the document to Recently deleted. Keys and files stay until the purge. Deleting a
    /// document already in Recently deleted changes nothing, so its 30-day timer never restarts.
    public func delete(_ id: DocumentID) throws {
        guard try entry(id).deletedAt == nil else { return }
        try update(id) { entry, _ in
            entry.deletedAt = self.now()
            return ([], [])
        }
    }

    /// Brings a document back from Recently deleted. Restoring a live document changes
    /// nothing and writes nothing.
    public func restore(_ id: DocumentID) throws {
        guard try entry(id).deletedAt != nil else { return }
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

    /// - Parameter rejectDeleted: throw `documentDeleted` for a document in Recently deleted.
    private func update(
        _ id: DocumentID,
        rejectDeleted: Bool = false,
        _ change: (inout IndexEntry, SymmetricKey) throws -> (newPages: [(PageID, Data)], obsoletePages: [PageID])
    ) throws {
        var documents = try requireState().index.documents
        guard let position = documents.firstIndex(where: { $0.id == id }) else { throw VaultError.documentNotFound }
        if rejectDeleted, documents[position].deletedAt != nil { throw VaultError.documentDeleted }
        let key = try documentKey(documents[position])
        let (newPages, obsoletePages) = try change(&documents[position], key)
        try commit(documents, newPages: newPages, obsoletePages: obsoletePages)
    }

    private func documentKey(_ entry: IndexEntry) throws -> SymmetricKey {
        try VaultCrypto.openDocumentKey(entry.sealedKey, with: requireState().wrapKey, documentID: entry.id)
    }

    private func entry(_ id: DocumentID) throws -> IndexEntry {
        guard let entry = try requireState().index.documents.first(where: { $0.id == id }) else {
            throw VaultError.documentNotFound
        }
        return entry
    }

    // swiftlint:disable:next function_parameter_count - each is needed and labelled; a wrapper would hide them
    private func pageFile(
        _ data: Data, pageID: PageID, position: Int, documentID: DocumentID, key: SymmetricKey,
        sealedKey: Data
    ) throws -> Data {
        let sealed = try VaultCrypto.seal(data, with: key, as: .page(documentID, pageID))
        return try PageFile(
            header: PageHeader(
                docId: documentID, pageId: pageID, position: position,
                sealedKey: sealedKey),
            sealedContent: sealed
        ).encoded()
    }
}
