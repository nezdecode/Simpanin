//
//  BackgroundTime.swift
//  Simpanin
//
//  Created by Inez Amanda on 17/11/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import UIKit

/// iOS suspends an app a few seconds after it leaves, and a save still being written can hold a lock past that.
/// This asks for time until the lock has landed and its cleanup has deleted its files. UIKit's two calls come in
/// through `init`, so the tests stand in for them.
@MainActor
final class BackgroundTime {
    typealias Begin = (_ expired: @escaping @MainActor @Sendable () -> Void) -> UIBackgroundTaskIdentifier

    private let begin: Begin
    private let end: (UIBackgroundTaskIdentifier) -> Void
    private var running: [UIBackgroundTaskIdentifier] = []

    init(begin: @escaping Begin, end: @escaping (UIBackgroundTaskIdentifier) -> Void) {
        self.begin = begin
        self.end = end
    }

    static func live() -> BackgroundTime {
        BackgroundTime(
            begin: { UIApplication.shared.beginBackgroundTask(withName: "Lock", expirationHandler: $0) },
            end: { UIApplication.shared.endBackgroundTask($0) })
    }

    /// `cleanUp` calls its argument once its files are gone.
    func hold(until locking: Task<Void, Never>, then cleanUp: @escaping (@escaping () -> Void) -> Void) {
        // iOS's allowance is shared, so when it runs out, every task still running ends. Held strongly: UIKit
        // keeps the handler only until the task ends, and a nil self here would end nothing.
        let id = begin { self.endAll() }
        running.append(id)
        Task {
            await locking.value
            cleanUp { self.finish(id) }
        }
    }

    /// Once only for each id: ending one twice, or never, is a programming error UIKit punishes.
    private func finish(_ id: UIBackgroundTaskIdentifier) {
        guard let index = running.firstIndex(of: id) else { return }
        running.remove(at: index)
        end(id)
    }

    private func endAll() {
        for id in running { finish(id) }
    }
}
