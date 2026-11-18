//
//  LockSequence.swift
//  Simpanin
//
//  Created by Inez Amanda on 18/11/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import Observation

/// One lock or unlock at a time. A lock never waits for an open, so it can cancel a prompt; an open waits for
/// every lock already decided, so the store can't answer it from a vault it is about to lock.
@MainActor @Observable
final class LockSequence {
    /// Locks decided whose store call hasn't answered yet.
    private(set) var locksWaiting = 0
    /// The last lock decided. Each waits for the one before, so this one landing means all have.
    @ObservationIgnored private var locking: Task<Void, Never>?

    /// A lock or an open is still running, so the lock screen holds Buka back.
    var isBusy: Bool { locksWaiting > 0 || opening != nil }
    /// True once a busy stretch has outlasted `waitBeforeShowing`, so a wait that ends at once shows no indicator.
    private(set) var showsWaiting = false
    @ObservationIgnored private let waitBeforeShowing: @MainActor () async -> Void
    /// Counts each start and end of a busy stretch, so a timer from an earlier one can't show the indicator.
    @ObservationIgnored private var stretch = 0

    /// `waitBeforeShowing`: 300 ms, long enough that a lock landing at once shows nothing.
    init(waitBeforeShowing: @escaping @MainActor () async -> Void = { try? await Task.sleep(for: .milliseconds(300)) })
    {
        self.waitBeforeShowing = waitBeforeShowing
    }

    /// Starts a lock's store half once every earlier lock has landed.
    func lock(_ finish: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
        change { locksWaiting += 1 }
        let previous = locking
        let task = Task { [weak self] in
            await previous?.value
            await finish()
            self?.change { self?.locksWaiting -= 1 }
        }
        locking = task
        return task
    }

    /// The open in flight, cleared as its task's last step, so a finished open is never awaited again.
    private(set) var opening: Task<Void, Never>?

    /// Runs one open. Callers settle first and start it with no await in between, so no two overlap, and no
    /// second caller joins an open a lock has already lost.
    func open(_ body: @escaping @MainActor () async -> Void) async {
        let task = Task { [weak self] in
            await body()
            self?.change { self?.opening = nil }
        }
        change { opening = task }
        await task.value
    }

    /// Waits until every lock decided so far has landed and the open in flight has ended, and for any that start
    /// meanwhile.
    func settle() async {
        // The last lock ending means all have, and it counts itself down before it ends, so a finished task is
        // never awaited twice.
        while true {
            if locksWaiting > 0, let locking {
                await locking.value
            } else if let opening {
                await opening.value
            } else {
                return
            }
        }
    }

    private func change(_ update: () -> Void) {
        let wasBusy = isBusy
        update()
        guard isBusy != wasBusy else { return }
        stretch += 1
        guard isBusy else {
            showsWaiting = false
            return
        }
        let current = stretch
        Task { [weak self, waitBeforeShowing] in
            await waitBeforeShowing()
            guard let self, stretch == current else { return }
            showsWaiting = true
        }
    }
}
