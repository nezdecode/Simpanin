//
//  LockControllerLockingTests.swift
//  SimpaninTests
//
//  Created by Inez Amanda on 14/11/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import Testing

@testable import Simpanin
@testable import VaultCore

/// A store that is busy with a write answers a lock late. Nothing may show meanwhile, and what was being
/// written still counts as saved.
@MainActor
@Suite("Lock controller, while the store locks")
struct LockControllerLockingTests {
    let clock = ManualClock()

    /// Open, over a store whose next lock waits until the test releases it.
    func unlocked(_ vault: FakeVault) async -> LockController {
        let clock = clock
        let controller = LockController(
            vault: vault, now: { clock.now }, autoLock: .oneMinute, passcode: { .set }, vaultExists: { true },
            vaultIsEmpty: { false }, protectedDataAvailable: { true })
        await controller.sceneDidBecomeActive()
        await vault.gateNextLock()
        return controller
    }

    @Test func returningAfterTheTimeoutHidesTheContentWhileTheStoreLocks() async {
        let vault = FakeVault([])
        let controller = await unlocked(vault)
        controller.sceneDidBecomeInactive()
        controller.sceneDidEnterBackground()
        clock.advance(by: .seconds(60))
        let returning = Task { await controller.sceneDidBecomeActive() }
        #expect(await vault.waitUntilLocking())
        #expect(controller.contentHidden)
        await vault.releaseLock()
        await returning.value
        #expect(controller.state == .unlocked)
        #expect(!controller.contentHidden)
        #expect(await vault.openCount == 2)
    }

    @Test func tappingLockHidesTheContentBeforeTheStoreAnswers() async {
        let vault = FakeVault([])
        let controller = await unlocked(vault)
        let locking = Task { await controller.lock() }
        #expect(await vault.waitUntilLocking())
        #expect(controller.contentHidden)
        // The screens stay until the store has answered: what they report on leaving mustn't reach the lock
        // before it has read what was in progress.
        #expect(controller.state == .unlocked)
        await vault.releaseLock()
        await locking.value
        #expect(controller.state == .locked)
    }

    @Test func phoneLockingHidesTheContentBeforeTheStoreAnswers() async {
        let vault = FakeVault([])
        let controller = await unlocked(vault)
        let locking = Task { await controller.protectedDataWillBecomeUnavailable() }
        #expect(await vault.waitUntilLocking())
        #expect(controller.contentHidden)
        await vault.releaseLock()
        await locking.value
        #expect(controller.state == .locked)
    }

    /// The store finishes a write before it locks, and the save reports itself before the lock goes on.
    @Test func aScanSavedWhileTheStoreLocksIsntCalledDropped() async {
        let vault = FakeVault([])
        let controller = await unlocked(vault)
        controller.scanStarted(.camera)
        let locking = Task { await controller.lock() }
        #expect(await vault.waitUntilLocking())
        controller.scanEnded()
        await vault.releaseLock()
        await locking.value
        await controller.unlock()
        #expect(controller.state == .unlocked)
        #expect(controller.notices.isEmpty)
    }

    @Test func anEditSavedWhileTheStoreLocksIsntCalledDropped() async {
        let vault = FakeVault([])
        let controller = await unlocked(vault)
        controller.editChanged(true)
        let locking = Task { await controller.lock() }
        #expect(await vault.waitUntilLocking())
        controller.editChanged(false)
        await vault.releaseLock()
        await locking.value
        await controller.unlock()
        #expect(controller.state == .unlocked)
        #expect(controller.notices.isEmpty)
    }

    /// The cover is cleared when the scene becomes active, not after the relock: later, it would undo the
    /// cover of a scene that went inactive meanwhile, and the open that follows would show the content.
    @Test func leavingAgainWhileTheStoreLocksKeepsTheCover() async {
        let vault = FakeVault([])
        let controller = await unlocked(vault)
        controller.sceneDidBecomeInactive()
        controller.sceneDidEnterBackground()
        clock.advance(by: .seconds(60))
        let returning = Task { await controller.sceneDidBecomeActive() }
        #expect(await vault.waitUntilLocking())
        controller.sceneDidBecomeInactive()
        await vault.releaseLock()
        await returning.value
        #expect(controller.state == .unlocked)
        #expect(controller.coverShown)
        #expect(controller.contentHidden)
    }

    /// The app can go to the background again while the store still answers a relock. The prompt then waits
    /// for the return: a phone can't show one in the background, and a refused one would leave an error screen.
    @Test func leavingToTheBackgroundWhileTheStoreLocksLeavesThePromptForTheReturn() async {
        let vault = FakeVault([])
        let controller = await unlocked(vault)
        controller.sceneDidEnterBackground()
        clock.advance(by: .seconds(60))
        let returning = Task { await controller.sceneDidBecomeActive() }
        #expect(await vault.waitUntilLocking())
        controller.sceneDidBecomeInactive()
        controller.sceneDidEnterBackground()
        await vault.releaseLock()
        await returning.value
        #expect(controller.state == .locked)
        #expect(await vault.openCount == 1)
        await controller.sceneDidBecomeActive()
        #expect(controller.state == .unlocked)
        #expect(await vault.openCount == 2)
        #expect(await vault.lockCount == 1)
    }

    /// Control Centre or a call can make the app inactive and active again while the store still answers a
    /// relock. That second activation is no return from the background, so it doesn't lock again.
    @Test func aMomentInactiveWhileTheStoreLocksDoesNotLockTwice() async {
        let vault = FakeVault([])
        let controller = await unlocked(vault)
        controller.sceneDidEnterBackground()
        clock.advance(by: .seconds(60))
        let returning = Task { await controller.sceneDidBecomeActive() }
        #expect(await vault.waitUntilLocking())
        controller.sceneDidBecomeInactive()
        await controller.sceneDidBecomeActive()
        await vault.releaseLock()
        await returning.value
        #expect(controller.state == .unlocked)
        #expect(await vault.lockCount == 1)
        #expect(await vault.openCount == 2)
    }
}
