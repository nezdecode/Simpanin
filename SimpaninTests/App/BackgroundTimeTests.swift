//
//  BackgroundTimeTests.swift
//  SimpaninTests
//
//  Created by Inez Amanda on 17/11/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Testing
import UIKit

@testable import Simpanin

/// Stands in for UIKit: hands out ids, keeps each expiry handler, and records what was ended.
@MainActor
final class FakeBackgroundTasks {
    private(set) var ended: [Int] = []
    private(set) var expiries: [@MainActor @Sendable () -> Void] = []
    /// One per `cleanUp` call, in order; calling one says the cleanup has finished.
    private(set) var cleanups: [() -> Void] = []

    func time() -> BackgroundTime {
        BackgroundTime(
            begin: { expired in
                self.expiries.append(expired)
                return UIBackgroundTaskIdentifier(rawValue: self.expiries.count)
            }, end: { self.ended.append($0.rawValue) })
    }

    func cleanUp(_ done: @escaping () -> Void) { cleanups.append(done) }

    /// False if `count` cleanups didn't start within two seconds, so a broken hold fails instead of hanging.
    func waitForCleanups(_ count: Int) async -> Bool {
        for _ in 0..<2_000 where cleanups.count < count {
            try? await Task.sleep(for: .milliseconds(1))
        }
        return cleanups.count >= count
    }
}

@MainActor
@Suite("Background time")
struct BackgroundTimeTests {
    /// Ended too early, the app can be suspended with the lock's copies still on disk; never ended, iOS stops it.
    @Test func aTaskEndsOnceAfterTheLockAndItsCleanup() async throws {
        let tasks = FakeBackgroundTasks()
        let time = tasks.time()
        let (gate, open) = AsyncStream<Void>.makeStream()
        let locking = Task { for await _ in gate {} }
        time.hold(until: locking, then: tasks.cleanUp)
        // Time for the hold's task to run: the cleanup must still wait for the lock.
        try await Task.sleep(for: .milliseconds(20))
        #expect(tasks.cleanups.isEmpty)
        #expect(tasks.ended.isEmpty)
        open.finish()
        #expect(await tasks.waitForCleanups(1))
        #expect(tasks.ended.isEmpty)
        let done = try #require(tasks.cleanups.first)
        done()
        done()
        #expect(tasks.ended == [1])
    }

    /// iOS gives one shared allowance, so when it runs out every task still running is ended, each once.
    @Test func anExpiryEndsEveryTaskStillRunning() async throws {
        let tasks = FakeBackgroundTasks()
        let time = tasks.time()
        let (gate, open) = AsyncStream<Void>.makeStream()
        let locking = Task { for await _ in gate {} }
        time.hold(until: locking, then: tasks.cleanUp)
        time.hold(until: locking, then: tasks.cleanUp)
        let expired = try #require(tasks.expiries.first)
        expired()
        #expect(tasks.ended.sorted() == [1, 2])
        open.finish()
        #expect(await tasks.waitForCleanups(2))
        for done in tasks.cleanups { done() }
        #expect(tasks.ended.sorted() == [1, 2])
    }

    @Test func twoLeavesInARowEachEndTheirOwn() async throws {
        let tasks = FakeBackgroundTasks()
        let time = tasks.time()
        time.hold(until: Task {}, then: tasks.cleanUp)
        time.hold(until: Task {}, then: tasks.cleanUp)
        #expect(await tasks.waitForCleanups(2))
        let first = try #require(tasks.cleanups.first)
        let second = try #require(tasks.cleanups.last)
        second()
        #expect(tasks.ended == [2])
        first()
        #expect(tasks.ended == [2, 1])
    }
}
