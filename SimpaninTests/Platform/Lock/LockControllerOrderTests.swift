//
//  LockControllerOrderTests.swift
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
@testable import VaultCore

/// One lock or unlock at a time: a lock never waits for an open, an open waits for every lock already decided and
/// for the open before it, and a return waits for both.
@MainActor
@Suite("Lock controller, one lock or unlock at a time", .timeLimit(.minutes(1)))
struct LockControllerOrderTests {
    let clock = ManualClock()

    func unlocked(_ vault: FakeVault, autoLock: AutoLock = .oneMinute) async -> LockController {
        let clock = clock
        let controller = LockController.make(vault, now: { clock.now }, autoLock: autoLock)
        await controller.sceneDidBecomeActive()
        return controller
    }

    /// Long enough for an open that doesn't wait to reach the fake store, which answers at once.
    func letTheMainActorRun() async {
        try? await Task.sleep(for: .milliseconds(100))
    }

    /// Buka while a second lock is still on its way: the store could answer an open that ran first from the vault
    /// it is about to lock, with no prompt.
    @Test func anUnlockWaitsForALockStillLanding() async {
        let vault = FakeVault([])
        let controller = await unlocked(vault)
        await controller.lock()
        #expect(controller.state == .locked)
        await vault.gateNextLock()
        let locking = Task { await controller.protectedDataWillBecomeUnavailable() }
        #expect(await vault.waitUntilLocking())
        let opening = Task { await controller.unlock() }
        await letTheMainActorRun()
        #expect(await vault.openCount == 1)
        await vault.releaseLock()
        await locking.value
        await opening.value
        #expect(controller.state == .unlocked)
        #expect(await vault.openCount == 2)
    }

    /// A Kunci or a phone lock still waiting for a busy store when the app leaves: the return waits for it, then
    /// prompts once, as it does when the lock has already landed.
    @Test(arguments: [false, true], [AutoLock.oneMinute, .immediately])
    func aReturnWaitsForALockStillLandingAndPromptsOnce(phoneLock: Bool, autoLock: AutoLock) async {
        let vault = FakeVault([])
        let controller = await unlocked(vault, autoLock: autoLock)
        await vault.gateNextLock()
        let locking = Task {
            if phoneLock {
                await controller.protectedDataWillBecomeUnavailable()
            } else {
                await controller.lock()
            }
        }
        #expect(await vault.waitUntilLocking())
        controller.sceneDidBecomeInactive()
        controller.sceneDidEnterBackground()
        let returning = Task { await controller.sceneDidBecomeActive() }
        await letTheMainActorRun()
        #expect(await vault.openCount == 1)
        await vault.releaseLock()
        await locking.value
        await returning.value
        #expect(controller.state == .unlocked)
        #expect(await vault.openCount == 2)
    }
}
