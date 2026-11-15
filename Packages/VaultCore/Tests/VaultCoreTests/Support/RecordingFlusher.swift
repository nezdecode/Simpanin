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
