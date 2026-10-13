//
//  TestSupport.swift
//  VaultCoreTests
//
//  Created by Inez Amanda on 4/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Crypto
import Foundation
import Synchronization
import Testing

@testable import VaultCore

// MARK: - Key store (tests only; never shipped)

actor InMemoryKeyStore: KeyStore {
    enum ReadFailure: Sendable {
        /// Like errSecAuthFailed (-25293), after the passcode is removed or Face ID fails.
        case locked
        /// Like errSecInteractionNotAllowed (-25308).
        case interactionNotAllowed
        /// Any error that is not a KeyStoreError at all.
        case unexpected
    }

    struct UnexpectedError: Error {}

    enum CreateFailure: Sendable {
        /// Adding the item fails with this Keychain status, for example with no device passcode.
        case status(Int32)
        /// Another process created the item between our read and our create.
        case alreadyExists
    }

    private var keys: [VaultID: SymmetricKey] = [:]
    private(set) var createCount = 0
    private(set) var deleteCount = 0
    var readFailure: ReadFailure?
    /// Makes `deleteVaultKey` fail with this status.
    var deleteFailureStatus: Int32?
    var createFailure: CreateFailure?

    init(keys: [VaultID: SymmetricKey] = [:]) { self.keys = keys }

    func setReadFailure(_ failure: ReadFailure?) { readFailure = failure }
    func setDeleteFailure(status: Int32?) { deleteFailureStatus = status }
    func setCreateFailure(_ failure: CreateFailure?) { createFailure = failure }
    func setKey(_ key: SymmetricKey?, for vaultID: VaultID) { keys[vaultID] = key }
    func key(for vaultID: VaultID) -> SymmetricKey? { keys[vaultID] }

    func readVaultKey(for vaultID: VaultID) async throws -> SymmetricKey {
        switch readFailure {
        case .locked: throw KeyStoreError.unavailable(status: -25293)
        case .interactionNotAllowed: throw KeyStoreError.unavailable(status: -25308)
        case .unexpected: throw UnexpectedError()
        case nil: break
        }
        guard let key = keys[vaultID] else { throw KeyStoreError.itemNotFound }
        return key
    }

    func createVaultKey(for vaultID: VaultID) async throws -> SymmetricKey {
        createCount += 1
        switch createFailure {
        case .status(let status): throw KeyStoreError.unavailable(status: status)
        case .alreadyExists: throw KeyStoreError.itemAlreadyExists
        case nil: break
        }
        guard keys[vaultID] == nil else { throw KeyStoreError.itemAlreadyExists }
        let key = VaultCrypto.newKey()
        keys[vaultID] = key
        return key
    }

    func deleteVaultKey(for vaultID: VaultID) async throws {
        deleteCount += 1
        if let deleteFailureStatus { throw KeyStoreError.unavailable(status: deleteFailureStatus) }
        guard keys[vaultID] != nil else { throw KeyStoreError.itemNotFound }
        keys[vaultID] = nil
    }
}

// MARK: - Clock

final class TestClock: VaultClock {
    private let date: Mutex<Date>
    init(_ now: Date = Date()) { date = Mutex(now) }
    var now: Date { date.withLock { $0 } }
    func set(_ now: Date) { date.withLock { $0 = now } }
    func advance(by seconds: TimeInterval) { date.withLock { $0 += seconds } }
}

// MARK: - File protection

/// Records which class each file was given, so tests on a Mac can check it.
final class RecordingProtector: FileProtector {
    private let log = Mutex<[(url: URL, protection: FileProtectionClass)]>([])
    var calls: [(url: URL, protection: FileProtectionClass)] { log.withLock { $0 } }
    func protect(_ url: URL, as protection: FileProtectionClass) throws {
        log.withLock { $0.append((url, protection)) }
    }
}

// MARK: - Flush

/// Records every flush and what was on disk at that moment.
final class RecordingFlusher: IndexFlusher {
    struct Event: Sendable {
        let url: URL
        /// The bytes of the flushed file at flush time.
        let contents: Data
        /// Page files present at flush time.
        let pageFiles: Set<String>
    }

    private let events = Mutex<[Event]>([])
    private let method: @Sendable (URL) -> FlushMethod
    private let failure: (any Error & Sendable)?
    /// Fail only when flushing this path. With nil, every flush fails if `failure` is set.
    private let failOnlyAt: URL?
    private let pagesDirectory: URL

    init(
        pagesDirectory: URL, method: @escaping @Sendable (URL) -> FlushMethod = { _ in .fullFsync },
        failure: (any Error & Sendable)? = nil, failOnlyAt: URL? = nil
    ) {
        self.pagesDirectory = pagesDirectory
        self.method = method
        self.failure = failure
        self.failOnlyAt = failOnlyAt
    }

    var recorded: [Event] { events.withLock { $0 } }

    func flush(_ url: URL) throws -> FlushMethod {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: pagesDirectory.path)) ?? []
        let event = Event(url: url, contents: (try? Data(contentsOf: url)) ?? Data(), pageFiles: Set(names))
        events.withLock { $0.append(event) }
        if let failure, failOnlyAt == nil || failOnlyAt?.standardizedFileURL.path == url.standardizedFileURL.path {
            throw failure
        }
        return method(url)
    }
}

// MARK: - Simulated crash

struct SimulatedCrash: Error {}

/// Once armed, records each write step and throws on the n-th (1-based). Steps before
/// `arm()`, such as those of `open()`, are ignored.
final class CrashSwitch: Sendable {
    private struct State {
        var armed = false
        var steps: [WriteStep] = []
        var crashAt: Int?
    }

    private let state: Mutex<State>
    init(crashAt: Int? = nil) { state = Mutex(State(crashAt: crashAt)) }
    var steps: [WriteStep] { state.withLock { $0.steps } }
    func arm() { state.withLock { $0.armed = true } }

    var hook: @Sendable (WriteStep) throws -> Void {
        { step in
            try self.state.withLock { current in
                guard current.armed else { return }
                current.steps.append(step)
                if current.steps.count == current.crashAt { throw SimulatedCrash() }
            }
        }
    }
}

// MARK: - A vault in a temporary directory

final class TestVault {
    let base: URL
    let keyStore: InMemoryKeyStore
    let clock: TestClock

    var root: URL { base.appending(path: "Vault", directoryHint: .isDirectory) }
    var projectionURL: URL { base.appending(path: "AppGroup/projection.json") }
    var pagesDirectory: URL { root.appending(path: "pages", directoryHint: .isDirectory) }
    var indexURL: URL { root.appending(path: "index.enc") }
    var previousIndexURL: URL { root.appending(path: "index.prev.enc") }
    var headerURL: URL { root.appending(path: "vault.json") }
    /// Application Support/Quarantine in the app.
    var quarantineURL: URL { base.appending(path: "Quarantine", directoryHint: .isDirectory) }

    init(keyStore: InMemoryKeyStore = InMemoryKeyStore(), clock: TestClock = TestClock()) throws {
        base = FileManager.default.temporaryDirectory
            .appending(path: "VaultCoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        self.keyStore = keyStore
        self.clock = clock
    }

    deinit { try? FileManager.default.removeItem(at: base) }

    func makeStore(crash: CrashSwitch? = nil, flusher: (any IndexFlusher)? = nil) -> VaultStore {
        VaultStore(
            rootDirectory: root, projectionURL: projectionURL, keyStore: keyStore,
            clock: clock, crashHook: crash?.hook, flusher: flusher ?? FileSystemFlusher())
    }

    /// A copy of this vault (same key store contents, own clock) in a new directory.
    func copy(clock: TestClock? = nil) async throws -> TestVault {
        let copy = try TestVault(keyStore: InMemoryKeyStore(), clock: clock ?? TestClock(self.clock.now))
        try FileManager.default.removeItem(at: copy.base)
        try FileManager.default.copyItem(at: base, to: copy.base)
        if let header = try? header(), let key = await keyStore.key(for: header.vaultId) {
            await copy.keyStore.setKey(key, for: header.vaultId)
        }
        return copy
    }

    func header() throws -> VaultHeader {
        try VaultJSON.decoder.decode(VaultHeader.self, from: Data(contentsOf: headerURL))
    }

    func pageFiles() throws -> [URL] {
        guard FileManager.default.fileExists(atPath: pagesDirectory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: pagesDirectory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "enc" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    func pageURL(_ id: PageID) -> URL { pagesDirectory.appending(path: "\(id.string).enc") }

    /// Every file under `directory`, keyed by its path relative to `directory`.
    static func files(in directory: URL) throws -> [String: Data] {
        var result: [String: Data] = [:]
        let base = directory.standardizedFileURL.path + "/"
        if let enumerator = FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: [.isRegularFileKey])
        {
            for case let url as URL in enumerator
            where (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true {
                result[String(url.standardizedFileURL.path.dropFirst(base.count))] = try Data(contentsOf: url)
            }
        }
        return result
    }

    /// Every regular file under the vault root and the projection.
    func allFiles() throws -> [URL] {
        var files: [URL] = []
        if let enumerator = FileManager.default.enumerator(at: base, includingPropertiesForKeys: [.isRegularFileKey]) {
            for case let url as URL in enumerator
            where (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true {
                files.append(url)
            }
        }
        return files
    }

    /// Opens an index file with the vault's real index key, for inspection.
    func readIndex(at url: URL) async throws -> VaultIndex {
        let header = try header()
        let key = try #require(await keyStore.key(for: header.vaultId))
        let indexKey = VaultCrypto.indexKey(from: key, vaultID: header.vaultId)
        let plain = try VaultCrypto.open(Data(contentsOf: url), with: indexKey, as: .index(header.vaultId))
        return try VaultJSON.decoder.decode(VaultIndex.self, from: plain)
    }

    func projection() throws -> Projection {
        try VaultJSON.decoder.decode(Projection.self, from: Data(contentsOf: projectionURL))
    }
}

// MARK: - Synthetic data (never real people)

enum Synthetic {
    /// NIK with province code 00, which no real region uses.
    static let nik = "0012341708900001"
    static let name = "BUDI CONTOH"
    static let simNumber = "0000-0000-000001"

    static let ktpFields = DocumentFields(["nik": nik, "name": name])
    static let simFields = DocumentFields(["number": simNumber, "name": name])
    static let simExpiry = CalendarDate(year: 2030, month: 8, day: 17)!

    /// A scan-sized stand-in, filled 8 bytes at a time so a 15 MB page takes milliseconds.
    static func largePage(bytes count: Int) -> Data {
        var data = Data(count: count)
        data.withUnsafeMutableBytes { raw in
            var random: UInt64 = 0x9E37_79B9_7F4A_7C15
            let words = raw.bindMemory(to: UInt64.self)
            for i in words.indices {
                random ^= random << 13
                random ^= random >> 7
                random ^= random << 17
                words[i] = random
            }
        }
        return data
    }

    /// Stand-ins for image bytes. Not real images, so nothing to leak.
    static func page(_ label: String, size: Int = 2_000) -> Data {
        var data = Data("SYNTHETIC-PAGE-\(label)|".utf8)
        var random = UInt32(truncatingIfNeeded: label.hashValueStable)
        while data.count < size {
            random = random &* 1_664_525 &+ 1_013_904_223
            data.append(UInt8(truncatingIfNeeded: random >> 24))
        }
        return data
    }
}

extension String {
    /// A hash that is the same on every run (String.hashValue is seeded per process).
    var hashValueStable: UInt64 {
        utf8.reduce(14_695_981_039_346_656_037) { ($0 ^ UInt64($1)) &* 1_099_511_628_211 }
    }
}

extension Data {
    func contains(bytes needle: Data) -> Bool {
        !needle.isEmpty && range(of: needle) != nil
    }
}

// MARK: - Whole-vault snapshot for comparing states

/// A document's full content, without ids (ids are random per run).
struct DocumentSnapshot: Hashable, Comparable {
    var type: String
    var createdAt: Date
    var updatedAt: Date
    var expiry: String?
    var pinned: Bool
    var deletedAt: Date?
    var fields: [String: String]
    var pages: [Data]

    static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.createdAt, lhs.type, lhs.pages.count) < (rhs.createdAt, rhs.type, rhs.pages.count)
    }
}

extension VaultStore {
    func snapshot() throws -> [DocumentSnapshot] {
        try (documents() + recentlyDeleted()).map { doc in
            DocumentSnapshot(
                type: doc.type.rawValue, createdAt: doc.createdAt, updatedAt: doc.updatedAt,
                expiry: doc.expiry?.string, pinned: doc.pinned, deletedAt: doc.deletedAt,
                fields: try fields(of: doc.id).values,
                pages: try pages(of: doc.id).map(\.data)
            )
        }.sorted()
    }
}
