//
//  VaultStore.swift
//  VaultCore
//
//  Created by Inez Amanda on 4/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Crypto
import Foundation

/// Where the index came from when the vault was opened.
public enum IndexSource: Sendable, Equatable {
    /// A new vault was created.
    case new
    /// index.enc opened normally.
    case current
    /// index.enc was missing, unreadable or older, so index.prev.enc was used.
    case previous
    /// Neither index file worked, so documents were rebuilt from page headers. Fields are lost.
    case recovered
}

/// What `open()` did. It only holds counts, never ids or contents, so the app may log it.
public struct OpenReport: Sendable, Equatable {
    public var createdVault = false
    public var indexSource = IndexSource.current
    public var purgedDocuments = 0
    public var removedOrphanPages = 0
    /// Page files that could not be opened. They are never deleted.
    public var unreadablePages = 0
    /// Opened from index.prev.enc, so the newest change may be lost.
    public var newestChangeMayBeLost = false
    /// Rebuilt from page images. Fields are empty and deleted documents may be back.
    public var recoveredFromPages = false
    /// The disk was full, so a repair or purge couldn't be written. The vault is open with what
    /// was loaded; the next save writes the repair, and a later open retries the purge.
    public var repairWaitingForSpace = false
}

/// A step of the write order, reported to the crash-simulation hook in tests.
enum WriteStep: Sendable, Equatable {
    case pagesWritten, indexMovedToPrevious, indexWritten, obsoletePagesDeleted, projectionWritten
}

/// The encrypted document store. Every change goes through the write order in `commit`.
/// The code is split by topic across the VaultStore+*.swift files.
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
    /// How the last commit that flushed did it. `.fsync` if any of its flushes fell back.
    var lastFlushMethod: FlushMethod?
    /// How often the crash hook stopped a write, so `afterSave` never swallows a simulated crash.
    var crashHookStops = 0

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
    /// Bumped by every `lock()`, so an `open()` that was waiting for the key can tell.
    private var lockCount = 0
    var openTask: Task<OpenReport, any Error>?

    /// - Parameters:
    ///   - rootDirectory: the vault folder, Application Support/Vault in the app.
    ///   - projectionURL: projection.json, in the App Group container in the app.
    ///   - fileProtector: sets the Data Protection class. No default, so the app can't forget it.
    ///   - reminderOffsets: days before expiry written into the projection.
    public init(
        rootDirectory: URL, projectionURL: URL, keyStore: any KeyStore, clock: any VaultClock = SystemClock(),
        fileProtector: any FileProtector, reminderOffsets: [Int] = [60, 30, 7]
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

    var headerURL: URL { root.appending(path: Self.headerFileName) }

    /// The vault's header file. Part of the format, so it never changes.
    public static let headerFileName = "vault.json"

    /// Whether `rootDirectory` holds a vault, judged by its header. Reads no file contents and
    /// needs no key, so the app can ask before unlocking. An unreadable folder reads as no vault here,
    /// which only picks the no-passcode screen's text; `open()` itself never creates there.
    public nonisolated static func vaultExists(in rootDirectory: URL) -> Bool {
        FileManager.default.fileExists(atPath: rootDirectory.appending(path: headerFileName).path)
    }

    /// Whether `rootDirectory` holds nothing that could belong to a vault: no header, no index and
    /// no page file. Leftover temp files don't count, as they were never part of a save. Throws
    /// `fileUnavailable` when anything it looks for can't be checked, so an unreadable vault is never
    /// taken for an empty one.
    public nonisolated static func isEmpty(in rootDirectory: URL) throws -> Bool {
        let files = [
            rootDirectory.appending(path: headerFileName), indexURL(in: rootDirectory),
            previousIndexURL(in: rootDirectory),
        ]
        for file in files where try itemExists(file) { return false }
        return try !pageFilesExist(in: pagesDirectory(in: rootDirectory))
    }

    /// Only "no such file" means missing, as in `readFile(at:)`; `fileExists` would also say false for a
    /// folder it isn't allowed to look in.
    nonisolated static func itemExists(_ url: URL) throws -> Bool {
        do {
            _ = try FileManager.default.attributesOfItem(atPath: url.path)
            return true
        } catch CocoaError.fileReadNoSuchFile, CocoaError.fileNoSuchFile {
            return false
        } catch {
            throw VaultError.fileUnavailable
        }
    }

    var indexURL: URL { Self.indexURL(in: root) }
    var previousIndexURL: URL { Self.previousIndexURL(in: root) }
    var pagesDirectory: URL { Self.pagesDirectory(in: root) }
    nonisolated static func indexURL(in root: URL) -> URL { root.appending(path: "index.enc") }
    nonisolated static func previousIndexURL(in root: URL) -> URL { root.appending(path: "index.prev.enc") }
    nonisolated static func pagesDirectory(in root: URL) -> URL {
        root.appending(path: "pages", directoryHint: .isDirectory)
    }
    func pageURL(_ id: PageID) -> URL { pagesDirectory.appending(path: "\(id.string).enc") }

    /// Nil only when the file doesn't exist. Any other read error, like a file iOS keeps
    /// locked while the phone is locked, is `fileUnavailable`, never "missing" or "damaged".
    func readFile(at url: URL) throws -> Data? {
        do {
            return try Data(contentsOf: url)
        } catch CocoaError.fileReadNoSuchFile {
            return nil
        } catch {
            throw VaultError.fileUnavailable
        }
    }

    /// Creates a folder that's missing and gives it a class, which new files in it start with.
    /// A folder that's already there is left alone.
    func createFolder(_ url: URL, protection: FileProtectionClass) throws {
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try fileProtector.protect(url, as: protection)
    }

    // MARK: - Open and lock

    /// Unlocks the vault, then repairs the index if needed, removes orphan pages and purges.
    /// Creates a vault only when the vault folder can be read and holds no vault file.
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
        lockCount += 1
    }

    private func performOpen() async throws -> OpenReport {
        if state != nil, let lastReport { return lastReport }
        let lockCountAtStart = lockCount
        var report = OpenReport()

        let header: VaultHeader
        let vaultKey: SymmetricKey
        if try Self.itemExists(headerURL) {
            header = try readHeader(at: headerURL)
            vaultKey = try await readExistingVaultKey(header.vaultID)
        } else {
            // A folder that can't be read throws here, before any key is made.
            guard try Self.isEmpty(in: root) else { throw VaultError.vaultHeaderMissing }
            let vaultID = VaultID()
            vaultKey = try await readOrCreateNewVaultKey(vaultID)
            header = VaultHeader(vaultID: vaultID, keySlots: [KeySlot(kind: .device, createdAt: now())])
            try createFolder(root, protection: .complete)
            try createFolder(pagesDirectory, protection: .complete)
            try writeNew(VaultJSON.encoder.encode(header), to: headerURL, protection: .complete)
            report.createdVault = true
        }
        // lock() may have run while we waited for the key, and the files may have been
        // quarantined meanwhile. Nothing below waits, so this is the last chance to honour it.
        guard lockCount == lockCountAtStart else { throw VaultError.locked }
        guard vaultKey.bitCount == 256 else { throw VaultError.vaultUnreadable }
        try createFolder(pagesDirectory, protection: .complete)

        let indexKey = VaultCrypto.indexKey(from: vaultKey, vaultID: header.vaultID)
        let wrapKey = VaultCrypto.wrapKey(from: vaultKey, vaultID: header.vaultID)
        let loaded = try loadIndex(vaultID: header.vaultID, indexKey: indexKey, wrapKey: wrapKey)
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
            try repairAndCleanUp(loaded, &report)
        } catch {
            state = nil
            throw error
        }
        lastReport = report
        return report
    }

    /// Repairs the index, removes leftovers and purges, once the vault is unlocked. A full disk
    /// must not lock the user out: the vault opens with what was loaded, and a bad index.enc is
    /// replaced by the next save, never moved to index.prev.enc.
    private func repairAndCleanUp(_ loaded: LoadedIndex, _ report: inout OpenReport) throws {
        if loaded.source != .current || loaded.previousHoldsRemovedDocuments {
            // Replace a bad or stale index.enc, or finish an interrupted purge.
            do {
                try commit(loaded.index.documents)
            } catch VaultError.storageFull {
                report.repairWaitingForSpace = true
            }
        }
        try removeLeftoverTempFiles()
        if loaded.allowsOrphanCleanup {
            report.removedOrphanPages = try removeOrphanPages(unreadable: &report.unreadablePages)
        }
        do {
            report.purgedDocuments = try purgeExpired()
        } catch VaultError.storageFull {
            report.repairWaitingForSpace = true
        }
        try afterSave { try writeProjection(try requireState().index.documents) }
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
