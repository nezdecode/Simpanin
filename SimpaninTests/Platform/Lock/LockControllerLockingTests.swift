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
    func unlocked(_ vault: FakeVault, autoLock: AutoLock = .oneMinute) async -> LockController {
        let clock = clock
        let controller = LockController.make(vault, now: { clock.now }, autoLock: autoLock)
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
        // The activation after the blip waits for the lock like any other, so it runs beside the release.
        let blip = Task { await controller.sceneDidBecomeActive() }
        await vault.releaseLock()
        await returning.value
        await blip.value
        #expect(controller.state == .unlocked)
        #expect(await vault.lockCount == 1)
        #expect(await vault.openCount == 2)
    }

    // MARK: "Langsung" locks as the app leaves

    /// A return during the lock the leave started waits for it rather than locking again, so the store has
    /// locked before anything opens.
    @Test func theReturnWaitsForTheLockTheLeaveStarted() async {
        let vault = FakeVault([])
        let controller = await unlocked(vault, autoLock: .immediately)
        controller.sceneDidBecomeInactive()
        let leaving = controller.sceneDidEnterBackground()
        #expect(await vault.waitUntilLocking())
        let returning = Task { await controller.sceneDidBecomeActive() }
        await Task.yield()
        #expect(controller.contentHidden)
        #expect(await vault.openCount == 1)
        await vault.releaseLock()
        await returning.value
        await leaving?.value
        #expect(controller.state == .unlocked)
        #expect(await vault.lockCount == 1)
        #expect(await vault.openCount == 2)
    }

    @Test func leavingAgainBeforeTheLeaveLockLandsLeavesThePromptForTheReturn() async {
        let vault = FakeVault([])
        let controller = await unlocked(vault, autoLock: .immediately)
        let first = controller.sceneDidEnterBackground()
        #expect(await vault.waitUntilLocking())
        let returning = Task { await controller.sceneDidBecomeActive() }
        await Task.yield()
        controller.sceneDidBecomeInactive()
        let second = controller.sceneDidEnterBackground()
        await vault.releaseLock()
        await returning.value
        await first?.value
        await second?.value
        #expect(controller.state == .locked)
        #expect(await vault.openCount == 1)
        await controller.sceneDidBecomeActive()
        #expect(controller.state == .unlocked)
        #expect(await vault.openCount == 2)
    }

    /// Control Centre or a call while the leave lock waits: that activation is no return, so one prompt.
    @Test func aMomentInactiveWhileTheLeaveLockWaitsDoesNotPromptTwice() async {
        let vault = FakeVault([])
        let controller = await unlocked(vault, autoLock: .immediately)
        let leaving = controller.sceneDidEnterBackground()
        #expect(await vault.waitUntilLocking())
        let returning = Task { await controller.sceneDidBecomeActive() }
        await Task.yield()
        controller.sceneDidBecomeInactive()
        let blip = Task { await controller.sceneDidBecomeActive() }
        await Task.yield()
        await vault.releaseLock()
        await returning.value
        await blip.value
        await leaving?.value
        #expect(controller.state == .unlocked)
        #expect(await vault.lockCount == 1)
        #expect(await vault.openCount == 2)
    }

    /// Two round trips while a save holds the first leave lock, so both returns wait for the same locks. Batal on
    /// the prompt that follows is the user's answer, and the other return doesn't ask again.
    @Test func aBatalOnTheFirstOfTwoQuickReturnsPromptsNoMore() async {
        let vault = FakeVault([.success(OpenReport()), .failure(.vaultKeyUnavailable(status: -128))])
        let controller = await unlocked(vault, autoLock: .immediately)
        controller.sceneDidBecomeInactive()
        controller.sceneDidEnterBackground()
        #expect(await vault.waitUntilLocking())
        let first = Task { await controller.sceneDidBecomeActive() }
        await Task.yield()
        // The first return has begun, so the second leave makes the next activation a return too, not a blip.
        #expect(!controller.coverShown)
        controller.sceneDidBecomeInactive()
        controller.sceneDidEnterBackground()
        let second = Task { await controller.sceneDidBecomeActive() }
        await Task.yield()
        await vault.releaseLock()
        await first.value
        await second.value
        #expect(controller.state == .locked)
        #expect(await vault.openCount == 2)
    }

    /// The phone unlocked and the app back: the return prompts, and the phone's notice comes during that prompt.
    /// Batal answers both, so the notice doesn't ask again.
    @Test(.timeLimit(.minutes(1))) func aPhoneUnlockDuringTheReturnsPromptAsksNoMoreAfterBatal() async {
        let vault = FakeVault([.success(OpenReport()), .failure(.vaultKeyUnavailable(status: -128))])
        let conditions = LaunchConditions()
        let controller = await conditions.waitingForThePhoneUnlock(vault, clock: clock, autoLock: .oneMinute)
        controller.sceneDidBecomeInactive()
        controller.sceneDidEnterBackground()
        conditions.protectedData = true
        await vault.gateNextOpen()
        let returning = Task { await controller.sceneDidBecomeActive() }
        #expect(await vault.waitUntilOpening())
        let notice = Task { await controller.protectedDataDidBecomeAvailable() }
        // Long enough for the notice to start waiting for the return's open.
        try? await Task.sleep(for: .milliseconds(100))
        await vault.release()
        await returning.value
        await notice.value
        #expect(controller.state == .locked)
        #expect(await vault.openCount == 2)
    }

    /// "Mulai vault baru" while the phone lock that came during the move is still landing: the create waits for it,
    /// finds the lock screen where it was tapped, and drops out.
    @Test func aCreateDropsOutWhenAPhoneLockLandsDuringItsWait() async {
        let vault = FakeVault([.failure(.vaultKeyMissing)])
        let conditions = LaunchConditions()
        conditions.headerExists = true
        conditions.empty = false
        let controller = conditions.makeController(vault, clock: clock)
        await controller.sceneDidBecomeActive()
        #expect(controller.state == .recovery(.keyMissing))
        await vault.gateNextLock()
        conditions.protectedData = false
        let locking = Task { await controller.protectedDataWillBecomeUnavailable() }
        #expect(await vault.waitUntilLocking())
        conditions.headerExists = false  // quarantined
        conditions.empty = true
        let creating = Task { await controller.createVault(then: nil) }
        // Long enough for the create to read its screen and start waiting before the lock lands.
        try? await Task.sleep(for: .milliseconds(100))
        await vault.releaseLock()
        await locking.value
        await creating.value
        #expect(controller.state == .locked)
        #expect(await vault.openCount == 1)
    }
}
