//
//  LockSequenceTests.swift
//  SimpaninTests
//
//  Created by Inez Amanda on 18/11/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import Testing

@testable import Simpanin

/// What the lock screen shows while a lock or an open still runs: Buka held back, and an indicator only once the
/// wait has lasted long enough to notice. Each wait before the indicator is a timer the test fires itself.
@MainActor
@Suite("Lock sequence, waiting", .timeLimit(.minutes(1)))
struct LockSequenceTests {
    let timers = Timers()

    func sequence() -> LockSequence {
        let timers = timers
        return LockSequence(waitBeforeShowing: { await timers.wait() })
    }

    /// Fires a timer once it's waiting; false if none started within two seconds.
    func fire(_ index: Int) async -> Bool {
        for _ in 0..<200 where timers.count <= index {
            try? await Task.sleep(for: .milliseconds(10))
        }
        guard timers.count > index else { return false }
        timers.fire(index)
        // Lets the timer's task run to its end.
        for _ in 0..<10 { await Task.yield() }
        return true
    }

    @Test func theCoverIsBusyWhileALockOrALostOpenIsStillRunning() async {
        let sequence = sequence()
        let lockGate = Gate()
        let locking = sequence.lock { await lockGate.wait() }
        #expect(sequence.isBusy)
        #expect(!sequence.showsWaiting)
        #expect(await fire(0))
        #expect(sequence.showsWaiting)
        lockGate.open()
        await locking.value
        #expect(!sequence.isBusy)
        #expect(!sequence.showsWaiting)

        let openGate = Gate()
        let opening = Task { await sequence.open { await openGate.wait() } }
        await Task.yield()
        #expect(sequence.isBusy)
        #expect(await fire(1))
        #expect(sequence.showsWaiting)
        openGate.open()
        await opening.value
        #expect(!sequence.isBusy)
        #expect(!sequence.showsWaiting)
    }

    /// A Kunci whose lock lands at once. Its timer, still waiting when the next wait starts, mustn't show the
    /// indicator in that one; only that wait's own timer does.
    @Test func theCoverShowsNoIndicatorForALockThatLandsAtOnce() async {
        let sequence = sequence()
        let locking = sequence.lock {}
        #expect(!sequence.showsWaiting)
        await locking.value
        let gate = Gate()
        let next = sequence.lock { await gate.wait() }
        #expect(await fire(0))
        #expect(!sequence.showsWaiting)
        #expect(await fire(1))
        #expect(sequence.showsWaiting)
        gate.open()
        await next.value
        #expect(!sequence.showsWaiting)
    }
}

/// The waits before the indicator, each held until the test fires it.
@MainActor
final class Timers {
    private var waiting: [CheckedContinuation<Void, Never>?] = []
    var count: Int { waiting.count }

    func wait() async {
        await withCheckedContinuation { waiting.append($0) }
    }

    func fire(_ index: Int) {
        waiting[index]?.resume()
        waiting[index] = nil
    }
}

/// Holds a lock's or an open's work until the test opens it.
@MainActor
final class Gate {
    private var isOpen = false
    private var waiting: CheckedContinuation<Void, Never>?

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiting = $0 }
    }

    func open() {
        isOpen = true
        waiting?.resume()
        waiting = nil
    }
}
