//
//  Fakes.swift
//  SimpaninTests
//
//  Created by Inez Amanda on 14/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import CoreGraphics
import Foundation
import Synchronization

@testable import Simpanin
@testable import VaultCore

/// Answers open() from a list of results. A gated open waits until the test releases it, like
/// a prompt that is still on screen.
actor FakeVault: VaultOpening {
    private var results: [Result<OpenReport, VaultError>]
    private(set) var openCount = 0
    private(set) var lockCount = 0
    private var gate: CheckedContinuation<Void, Never>?
    private let gated: Bool
    private let onlyFirstGated: Bool

    /// - Parameter onlyFirstGated: later opens answer at once, so a retry the test doesn't
    ///   expect fails the test instead of hanging it.
    init(_ results: [Result<OpenReport, VaultError>], gated: Bool = false, onlyFirstGated: Bool = false) {
        self.results = results
        self.gated = gated
        self.onlyFirstGated = onlyFirstGated
    }

    func open() async throws -> OpenReport {
        openCount += 1
        if gated, !onlyFirstGated || openCount == 1 { await withCheckedContinuation { gate = $0 } }
        let result = results.isEmpty ? .success(OpenReport()) : results.removeFirst()
        return try result.get()
    }

    func lock() async { lockCount += 1 }

    /// False if open() didn't start within two seconds, so a broken controller fails the test
    /// instead of hanging it.
    func waitUntilOpening() async -> Bool {
        for _ in 0..<2_000 where gate == nil {
            try? await Task.sleep(for: .milliseconds(1))
        }
        return gate != nil
    }

    func release() {
        gate?.resume()
        gate = nil
    }
}

final class FixedClock: VaultClock {
    private let date = Mutex(Date(timeIntervalSince1970: 1_790_000_000))
    var now: Date { date.withLock { $0 } }
    func advance(by seconds: TimeInterval) { date.withLock { $0 += seconds } }
}

/// Stands in for VaultStore's document calls, with documents kept in memory.
/// The hidden banner list kept in memory, as a test needs it.
final class FakeHiddenBanner: HiddenBannerStoring {
    private let stored = Mutex(HiddenBanner())
    var saved: HiddenBanner { stored.withLock { $0 } }
    func load() throws -> HiddenBanner { stored.withLock { $0 } }
    func save(_ hidden: HiddenBanner) throws { stored.withLock { $0 = hidden } }
}

actor FakeDocuments: DocumentStoring {
    private var live: [Document] = []
    private var bin: [Document] = []
    private(set) var created: [DocumentFields] = []
    private(set) var createdPages: [[Data]] = []
    private var failure: VaultError?
    private var loadFailure: VaultError?
    private var binFailure: VaultError?
    private var createGated = false
    private var createGate: CheckedContinuation<Void, Never>?

    func setFailure(_ failure: VaultError?) { self.failure = failure }
    func setLoadFailure(_ failure: VaultError?) { loadFailure = failure }
    func setBinFailure(_ failure: VaultError?) { binFailure = failure }
    /// The next createDocument waits until the test releases it, like a save still being written.
    func gateNextCreate() { createGated = true }

    /// False if no gated create started within two seconds, so a test fails instead of hanging.
    func waitUntilCreating() async -> Bool {
        for _ in 0..<2_000 where createGate == nil {
            try? await Task.sleep(for: .milliseconds(1))
        }
        return createGate != nil
    }

    func releaseCreate() {
        createGate?.resume()
        createGate = nil
    }

    func documents() async throws -> [Document] {
        if let loadFailure { throw loadFailure }
        return live
    }

    func recentlyDeleted() async throws -> [Document] {
        if let failure = loadFailure ?? binFailure { throw failure }
        return bin
    }

    // swiftlint:disable:next function_parameter_count - mirrors VaultStore.createDocument
    func createDocument(
        type: DocumentType, label: String?, expiry: CalendarDate?, pinned: Bool, fields: DocumentFields,
        pages: [Data]
    ) async throws -> DocumentID {
        if createGated {
            createGated = false
            await withCheckedContinuation { createGate = $0 }
        }
        if let failure { throw failure }
        let id = DocumentID()
        created.append(fields)
        createdPages.append(pages)
        live.append(
            Document(
                id: id, type: type, label: label, createdAt: .now, updatedAt: .now, expiry: expiry, pinned: pinned,
                deletedAt: nil, pageIDs: pages.map { _ in PageID() }))
        return id
    }

    func delete(_ id: DocumentID) async throws {
        if let failure { throw failure }
        guard let index = live.firstIndex(where: { $0.id == id }) else { return }
        var document = live.remove(at: index)
        document.deletedAt = .now
        bin.append(document)
    }

    /// Gone for good, as VaultCore purges Baru dihapus after 30 days.
    func purge(_ id: DocumentID) {
        live.removeAll { $0.id == id }
        bin.removeAll { $0.id == id }
    }

    func restore(_ id: DocumentID) async throws {
        if let failure { throw failure }
        guard let index = bin.firstIndex(where: { $0.id == id }) else { return }
        var document = bin.remove(at: index)
        document.deletedAt = nil
        live.append(document)
    }
}

/// Stands in for VaultStore's quarantine calls.
actor FakeQuarantine: QuarantineStoring {
    private(set) var quarantinedTo: [URL] = []
    private(set) var deleted: [QuarantinedVault] = []
    var listing = QuarantineListing(vaults: [], unreadableFolders: [])
    var failure: VaultError?
    var listingFailure: (any Error)?

    func setListing(_ listing: QuarantineListing) { self.listing = listing }
    func setFailure(_ failure: VaultError?) { self.failure = failure }
    func setListingFailure(_ failure: (any Error)?) { listingFailure = failure }

    func quarantineVault(to quarantineDirectory: URL) async throws -> URL? {
        if let failure { throw failure }
        quarantinedTo.append(quarantineDirectory)
        return quarantineDirectory.appending(path: "20261015-010000")
    }

    func quarantinedVaults(in quarantineDirectory: URL) async throws -> QuarantineListing {
        if let listingFailure { throw listingFailure }
        return listing
    }

    func deleteQuarantinedVault(_ vault: QuarantinedVault) async throws {
        if let failure { throw failure }
        deleted.append(vault)
        listing.vaults.removeAll { $0 == vault }
    }
}

/// Answers a page with the next list of lines. When gated, the first read waits until the test releases
/// it, like Vision still working when the vault locks; later reads answer at once, so a read the test
/// doesn't expect fails it instead of hanging it.
actor FakeRecognizer {
    private var answers: [[String]]
    private let failing: Bool
    private let gated: Bool
    private var gate: CheckedContinuation<Void, Never>?
    private(set) var methods: [RecognitionMethod] = []

    init(_ answers: [[String]], failing: Bool = false, gated: Bool = false) {
        self.answers = answers
        self.failing = failing
        self.gated = gated
    }

    nonisolated func using(_ method: RecognitionMethod) -> any TextRecognizer {
        Reader(fake: self, method: method)
    }

    private struct Reader: TextRecognizer {
        let fake: FakeRecognizer
        let method: RecognitionMethod
        func lines(in page: CGImage) async throws -> [String] { try await fake.read(method) }
    }

    private struct Failure: Error {}

    private func read(_ method: RecognitionMethod) async throws -> [String] {
        methods.append(method)
        if gated, methods.count == 1 { await withCheckedContinuation { gate = $0 } }
        if failing { throw Failure() }
        return answers.isEmpty ? [] : answers.removeFirst()
    }

    /// False if no read started within two seconds, so a broken model fails the test instead of hanging it.
    func waitUntilReading() async -> Bool {
        for _ in 0..<2_000 where gate == nil {
            try? await Task.sleep(for: .milliseconds(1))
        }
        return gate != nil
    }

    func release() {
        gate?.resume()
        gate = nil
    }
}

/// A protector that always fails, like a protection change the phone refuses while it's locked.
struct FailingProtector: FileProtector {
    func protect(_ url: URL, as protection: FileProtectionClass) throws {
        throw CocoaError(.fileWriteNoPermission)
    }
}

/// Records which class each path was given, so tests can check it without a device.
final class RecordingProtector: FileProtector {
    private let log = Mutex<[(url: URL, protection: FileProtectionClass)]>([])
    var calls: [(url: URL, protection: FileProtectionClass)] { log.withLock { $0 } }
    func protect(_ url: URL, as protection: FileProtectionClass) throws {
        log.withLock { $0.append((url, protection)) }
    }
}
