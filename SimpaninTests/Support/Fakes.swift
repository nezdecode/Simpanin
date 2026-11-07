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
actor FakeVault {
    private var results: [Result<OpenReport, VaultError>]
    private(set) var openCount = 0
    private(set) var lockCount = 0
    private var gate: CheckedContinuation<Void, Never>?
    private let gated: Bool
    private let onlyFirstGated: Bool
    private var nextGated = false

    /// - Parameter onlyFirstGated: later opens answer at once, so a retry the test doesn't
    ///   expect fails the test instead of hanging it.
    init(_ results: [Result<OpenReport, VaultError>], gated: Bool = false, onlyFirstGated: Bool = false) {
        self.results = results
        self.gated = gated
        self.onlyFirstGated = onlyFirstGated
    }

    /// Gates only the next open, for a test that reaches a state through opens that must not wait.
    func gateNextOpen() { nextGated = true }

    func open() async throws -> OpenReport {
        openCount += 1
        if gated && (!onlyFirstGated || openCount == 1) || nextGated {
            nextGated = false
            await withCheckedContinuation { gate = $0 }
        }
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

    /// Also withdraws a gate no open has reached, so a later open can't wait forever.
    func release() {
        nextGated = false
        gate?.resume()
        gate = nil
    }
}

// In an extension: declared on the actor, a conformance to a nonisolated protocol makes Swift 6.4 mark the
// actor's init nonisolated, and reject it, when a file using the actor is type-checked first.
extension FakeVault: VaultOpening {}

final class FixedClock: VaultClock {
    private let date = Mutex(Date(timeIntervalSince1970: 1_790_000_000))
    var now: Date { date.withLock { $0 } }
    func advance(by seconds: TimeInterval) { date.withLock { $0 += seconds } }
}

/// Keeps what was copied, instead of the system clipboard.
final class FakeClipboard: Clipboard {
    private(set) var copied: [String] = []
    func copy(_ text: String) { copied.append(text) }
}

/// The hidden banner list kept in memory, as a test needs it, with a read or a write that can fail.
final class FakeHiddenBanner: HiddenBannerStoring {
    private let stored = Mutex(HiddenBanner())
    private let loadFailure = Mutex<(any Error)?>(nil)
    private let saveFailure = Mutex<(any Error)?>(nil)
    var saved: HiddenBanner { stored.withLock { $0 } }
    func setLoadFailure(_ error: (any Error)?) { loadFailure.withLock { $0 = error } }
    func setSaveFailure(_ error: (any Error)?) { saveFailure.withLock { $0 = error } }

    func load() throws -> HiddenBanner {
        if let error = loadFailure.withLock({ $0 }) { throw error }
        return stored.withLock { $0 }
    }

    func save(_ hidden: HiddenBanner) throws {
        if let error = saveFailure.withLock({ $0 }) { throw error }
        stored.withLock { $0 = hidden }
    }
}

/// Stands in for VaultStore's quarantine calls.
actor FakeQuarantine {
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

extension FakeQuarantine: QuarantineStoring {}  // in an extension, see FakeVault

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
