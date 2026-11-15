//
//  RecordingFlusher.swift
//  VaultCoreTests
//
//  Created by Inez Amanda on 15/11/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import Synchronization

@testable import VaultCore

/// Records every flush and what was on disk at that moment. Once armed, it throws `FlushError`
/// for the flushes `failingAt` names.
final class RecordingFlusher: IndexFlusher {
    struct Event: Sendable {
        let url: URL
        /// The bytes of the flushed file at flush time.
        let contents: Data
        /// The bytes of index.enc at flush time, empty when there was none.
        let indexContents: Data
        /// Page files present at flush time.
        let pageFiles: Set<String>
        /// The flush threw, so its bytes may not have reached the disk.
        let failed: Bool
    }

    enum Target: Sendable {
        case everything
        case file(URL)
        /// Any file in pages/, whose names aren't known before a save.
        case pageFiles
    }

    private let events = Mutex<[Event]>([])
    private let failures = Mutex((skip: 0, left: 0))
    private let method: @Sendable (URL) -> FlushMethod
    private let target: Target
    private let pagesDirectory: URL

    init(
        pagesDirectory: URL, method: @escaping @Sendable (URL) -> FlushMethod = { _ in .fullFsync },
        failingAt target: Target = .everything
    ) {
        self.pagesDirectory = pagesDirectory
        self.method = method
        self.target = target
    }

    var recorded: [Event] { events.withLock { $0 } }

    /// Lets `skipping` matching flushes work, then fails the next `times`. Until then, nothing fails.
    func arm(times: Int = .max, skipping: Int = 0) { failures.withLock { $0 = (skipping, times) } }
    func disarm() { arm(times: 0) }

    func flush(_ url: URL) throws -> FlushMethod {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: pagesDirectory.path)) ?? []
        let indexURL = pagesDirectory.deletingLastPathComponent().appending(path: "index.enc")
        let fails = matches(url) && takeFailure()
        let event = Event(
            url: url, contents: (try? Data(contentsOf: url)) ?? Data(),
            indexContents: (try? Data(contentsOf: indexURL)) ?? Data(), pageFiles: Set(names), failed: fails)
        events.withLock { $0.append(event) }
        if fails { throw FlushError() }
        return method(url)
    }

    private func takeFailure() -> Bool {
        failures.withLock { state in
            if state.skip > 0 {
                state.skip -= 1
                return false
            }
            guard state.left > 0 else { return false }
            state.left -= 1
            return true
        }
    }

    private func matches(_ url: URL) -> Bool {
        switch target {
        case .everything: true
        case .file(let file): url.standardizedFileURL.path == file.standardizedFileURL.path
        case .pageFiles:
            url.deletingLastPathComponent().standardizedFileURL.path == pagesDirectory.standardizedFileURL.path
        }
    }
}
