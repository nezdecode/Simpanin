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
    /// The vault opened from index.prev.enc (index.enc was unreadable, stale, or missing
    /// after a crash), so the newest change may be lost. The app shows a one-time notice
    /// without a number, because the count cannot always be known.
    public var newestChangeMayBeLost = false
    /// Both index files were unusable and documents were rebuilt from page images: fields
    /// are empty and deleted documents may be back. The app shows a one-time notice.
    public var recoveredFromPages = false
}

/// A step of the write order, reported to the crash-simulation hook in tests.
enum WriteStep: Sendable, Equatable {
    case pagesWritten, indexMovedToPrevious, indexWritten, obsoletePagesDeleted, projectionWritten
}

/// The encrypted document store. Owns vault.json, the index files, the page files and the
/// projection, and follows the write order in the design doc for every change:
/// 1. new page files, 2. index.enc -> index.prev.enc then the new index.enc,
/// 3. delete page files the index no longer references, 4. projection.json.
///
/// This file holds the state, opening and locking. The rest is split by topic:
/// VaultStore+Documents (reading and changes), +WriteOrder (`commit`), +Recovery (loading
/// the index, page recovery, orphans), +Keys (vault.json and the vault key) and +Quarantine.
public actor VaultStore {
    /// Documents in Recently deleted are purged this long after `deletedAt`.
    public static let purgeDelay: TimeInterval = 30 * 86_400
    /// Unreferenced page files younger than this are left alone.
    public static let orphanMinimumAge: TimeInterval = 5 * 60

    let root: URL
    let projectionURL: URL
    let keyStore: any KeyStore
    let clock: any VaultClock
    let fileProtector: any FileProtector
    let reminderOffsets: [Int]
    let crashHook: (@Sendable (WriteStep) throws -> Void)?
    let flusher: any IndexFlusher
    /// The flush call of the last commit that flushed: `.fullFsync` only if every flush in it
    /// (new pages, pages folder, index, vault folder) got F_FULLFSYNC (tests and diagnostics).
    var lastFlushMethod: FlushMethod?

    struct OpenState {
        let header: VaultHeader
        let indexKey: SymmetricKey
        let wrapKey: SymmetricKey
        var index: VaultIndex
        /// True when index.enc on disk holds `index`. Only then may it become index.prev.enc.
        var indexFileIsCurrent: Bool
    }

    var state: OpenState?
    private var lastReport: OpenReport?
    var openTask: Task<OpenReport, any Error>?

    /// - Parameters:
    ///   - rootDirectory: the vault folder (Application Support/Vault in the app).
    ///   - projectionURL: projection.json (in the App Group container in the app).
    ///   - reminderOffsets: days before expiry written into the projection.
    public init(
        rootDirectory: URL, projectionURL: URL, keyStore: any KeyStore, clock: any VaultClock = SystemClock(),
        fileProtector: any FileProtector = NoFileProtection(), reminderOffsets: [Int] = [60, 30, 7]
    ) {
        self.init(
            rootDirectory: rootDirectory, projectionURL: projectionURL, keyStore: keyStore, clock: clock,
            fileProtector: fileProtector, reminderOffsets: reminderOffsets, crashHook: nil,
            flusher: FileSystemFlusher())
    }

    init(
        rootDirectory: URL, projectionURL: URL, keyStore: any KeyStore, clock: any VaultClock,
        fileProtector: any FileProtector = NoFileProtection(), reminderOffsets: [Int] = [60, 30, 7],
        crashHook: (@Sendable (WriteStep) throws -> Void)?, flusher: any IndexFlusher = FileSystemFlusher()
    ) {
        root = rootDirectory
        self.projectionURL = projectionURL
        self.keyStore = keyStore
        self.clock = clock
        self.fileProtector = fileProtector
        self.reminderOffsets = reminderOffsets
        self.crashHook = crashHook
        self.flusher = flusher
    }

    // MARK: - Paths

    var headerURL: URL { root.appending(path: "vault.json") }
    var indexURL: URL { root.appending(path: "index.enc") }
    var previousIndexURL: URL { root.appending(path: "index.prev.enc") }
    var pagesDirectory: URL { root.appending(path: "pages", directoryHint: .isDirectory) }
    func pageURL(_ id: PageID) -> URL { pagesDirectory.appending(path: "\(id.string).enc") }

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
        let fileManager = FileManager.default

        let header: VaultHeader
        let vaultKey: SymmetricKey
        if fileManager.fileExists(atPath: headerURL.path) {
            header = try readHeader(at: headerURL)
            vaultKey = try await readExistingVaultKey(header.vaultId)
        } else {
            guard try !vaultFilesExist() else { throw VaultError.vaultHeaderMissing }
            let vaultID = VaultID()
            vaultKey = try await readOrCreateNewVaultKey(vaultID)
            header = VaultHeader(vaultId: vaultID, keySlots: [KeySlot(kind: .device, createdAt: now())])
            try fileManager.createDirectory(at: pagesDirectory, withIntermediateDirectories: true)
            try write(VaultJSON.encoder.encode(header), to: headerURL, protection: .complete)
            report.createdVault = true
        }
        guard vaultKey.bitCount == 256 else { throw VaultError.vaultUnreadable }
        try fileManager.createDirectory(at: pagesDirectory, withIntermediateDirectories: true)

        let indexKey = VaultCrypto.indexKey(from: vaultKey, vaultID: header.vaultId)
        let wrapKey = VaultCrypto.wrapKey(from: vaultKey, vaultID: header.vaultId)
        let loaded = try loadIndex(vaultID: header.vaultId, indexKey: indexKey, wrapKey: wrapKey)
        report.indexSource = report.createdVault ? .new : loaded.source
        report.newestChangeMayBeLost = !report.createdVault && loaded.source == .previous
        report.recoveredFromPages =
            !report.createdVault && loaded.source == .recovered
            && !loaded.index.documents.isEmpty
        report.unreadablePages = loaded.unreadablePages
        state = OpenState(
            header: header, indexKey: indexKey, wrapKey: wrapKey, index: loaded.index,
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

    // MARK: - Helpers

    func requireState() throws -> OpenState {
        guard let state else { throw VaultError.locked }
        return state
    }

    /// Timestamps are whole seconds so they survive the ISO 8601 round trip exactly.
    func now() -> Date {
        Date(timeIntervalSince1970: clock.now.timeIntervalSince1970.rounded(.down))
    }

    func sealFields(_ fields: DocumentFields, key: SymmetricKey, documentID: DocumentID) throws -> Data {
        try VaultCrypto.seal(VaultJSON.encoder.encode(fields), with: key, as: .fields(documentID))
    }
}
