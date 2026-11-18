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

    /// Starts a lock's store half once every earlier lock has landed.
    func lock(_ finish: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
        locksWaiting += 1
        let previous = locking
        let task = Task { [weak self] in
            await previous?.value
            await finish()
            self?.locksWaiting -= 1
        }
        locking = task
        return task
    }

    /// Waits until every lock decided so far, and any decided meanwhile, has landed.
    func settle() async {
        // A lock decided meanwhile replaces `locking`, so look again. The last one ending means all have, and it
        // counts itself down before it ends, so a finished task is never awaited twice.
        while locksWaiting > 0, let locking { await locking.value }
    }
}
