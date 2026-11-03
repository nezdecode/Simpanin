//
//  LockControllerTests.swift
//  SimpaninTests
//
//  Created by Inez Amanda on 14/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import Synchronization
import Testing

@testable import Simpanin
@testable import VaultCore

@MainActor
@Suite("Lock controller")
struct LockControllerTests {
    let clock = FixedClock()

    func makeController(
        _ vault: FakeVault, passcode: PasscodeState = .set, vaultExists: Bool = true,
        protectedData: @escaping @MainActor () -> Bool = { true }
    ) -> LockController {
        LockController(
            vault: vault, clock: clock, autoLock: .oneMinute, passcode: { passcode }, vaultExists: { vaultExists },
            protectedDataAvailable: protectedData)
    }

    static func unavailable(_ status: Int32?) -> Result<OpenReport, VaultError> {
        .failure(.vaultKeyUnavailable(status: status))
    }

    // MARK: Lifecycle table

    @Test func launchPromptsOnce() async {
        let vault = FakeVault([])
        let controller = makeController(vault)
        await controller.sceneDidBecomeActive()
        #expect(controller.state == .unlocked)
        #expect(await vault.openCount == 1)
    }

    @Test func inactiveCoversContentButKeepsKeys() async {
        let vault = FakeVault([])
        let controller = makeController(vault)
        await controller.sceneDidBecomeActive()
        controller.sceneDidBecomeInactive()
        #expect(controller.coverShown && controller.contentHidden)
        await controller.sceneDidBecomeActive()
        #expect(!controller.coverShown && !controller.contentHidden)
        #expect(controller.state == .unlocked)
        #expect(await vault.openCount == 1)
        #expect(await vault.lockCount == 0)
    }

    @Test func returningBeforeTheTimeoutStaysUnlocked() async {
        let vault = FakeVault([])
        let controller = makeController(vault)
        await controller.sceneDidBecomeActive()
        controller.sceneDidEnterBackground()
        clock.advance(by: 59)
        await controller.sceneDidBecomeActive()
        #expect(controller.state == .unlocked)
        #expect(await vault.lockCount == 0)
        #expect(await vault.openCount == 1)
    }

    @Test func returningAfterTheTimeoutRelocksAndPrompts() async {
        let vault = FakeVault([])
        let controller = makeController(vault)
        await controller.sceneDidBecomeActive()
        controller.sceneDidEnterBackground()
        clock.advance(by: 60)
        await controller.sceneDidBecomeActive()
        #expect(await vault.lockCount == 1)
        #expect(await vault.openCount == 2)
        #expect(controller.state == .unlocked)
    }

    @Test func phoneLockingLocksAtOnce() async {
        let vault = FakeVault([])
        let controller = makeController(vault)
        await controller.sceneDidBecomeActive()
        await controller.protectedDataWillBecomeUnavailable()
        #expect(controller.state == .locked)
        #expect(await vault.lockCount == 1)
    }

    @Test func tappingLockLocksAtOnce() async {
        let vault = FakeVault([])
        let controller = makeController(vault)
        await controller.sceneDidBecomeActive()
        await controller.lock()
        #expect(controller.state == .locked)
        #expect(controller.contentHidden)
        #expect(await vault.lockCount == 1)
    }

    @Test func opensOnlyWhenProtectedDataIsAvailable() async {
        let vault = FakeVault([])
        let available = Mutex(false)
        let controller = makeController(vault, protectedData: { available.withLock { $0 } })
        await controller.sceneDidBecomeActive()
        #expect(await vault.openCount == 0)
        #expect(controller.state == .locked)
        available.withLock { $0 = true }
        await controller.protectedDataDidBecomeAvailable()
        #expect(await vault.openCount == 1)
        #expect(controller.state == .unlocked)
    }

    @Test func screenCaptureHidesContent() async {
        let controller = makeController(FakeVault([]))
        await controller.sceneDidBecomeActive()
        #expect(!controller.contentHidden)
        controller.screenCaptured = true
        #expect(controller.contentHidden)
    }

    // MARK: Recovery

    @Test func noPasscodeShowsAScreenWithoutAPrompt() async {
        let vault = FakeVault([])
        let controller = makeController(vault, passcode: .notSet, vaultExists: false)
        await controller.sceneDidBecomeActive()
        #expect(controller.state == .recovery(.passcodeNeeded))
        #expect(await vault.openCount == 0)
    }

    @Test func cancelKeepsTheCoverAndNeverPromptsByItself() async {
        let vault = FakeVault([Self.unavailable(-128)])
        let controller = makeController(vault)
        await controller.sceneDidBecomeActive()
        #expect(controller.state == .locked)
        // The prompt closing makes the app active again. That must not prompt again.
        controller.sceneDidBecomeInactive()
        await controller.sceneDidBecomeActive()
        #expect(await vault.openCount == 1)
        #expect(controller.state == .locked)
    }

    @Test func goingToTheHomeScreenDuringThePromptIsACancel() async {
        let vault = FakeVault([Self.unavailable(-25293), .success(OpenReport())], gated: true)
        let controller = makeController(vault)
        let opening = Task { await controller.sceneDidBecomeActive() }
        #expect(await vault.waitUntilOpening())
        #expect(controller.state == .unlocking)
        controller.sceneDidBecomeInactive()
        controller.sceneDidEnterBackground()
        await vault.release()
        await opening.value
        #expect(controller.state == .locked)
        #expect(await vault.openCount == 1)

        // Back from the home screen: one new prompt.
        let reopening = Task { await controller.sceneDidBecomeActive() }
        #expect(await vault.waitUntilOpening())
        await vault.release()
        await reopening.value
        #expect(controller.state == .unlocked)
        #expect(await vault.openCount == 2)
    }

    @Test func twoFailuresInARowShowTheScreenAndRetryStartsOver() async {
        let vault = FakeVault([Self.unavailable(nil), Self.unavailable(nil), Self.unavailable(nil)])
        let controller = makeController(vault)
        await controller.sceneDidBecomeActive()
        #expect(await vault.openCount == 2)  // prompted again once by itself
        #expect(controller.state == .recovery(.cannotOpenNow))

        // "Coba lagi" starts a fresh count: one failure prompts again, then it opens.
        await controller.unlock()
        #expect(await vault.openCount == 4)
        #expect(controller.state == .unlocked)
    }

    @Test func returningFromSettingsRetriesThePasscodeScreen() async {
        // "Settings link; retry on return": the user sets a passcode and comes back.
        let vault = FakeVault([])
        let passcode = Mutex(PasscodeState.notSet)
        let controller = LockController(
            vault: vault, clock: clock, passcode: { passcode.withLock { $0 } }, vaultExists: { false },
            protectedDataAvailable: { true })
        await controller.sceneDidBecomeActive()
        #expect(controller.state == .recovery(.passcodeNeeded))
        controller.sceneDidEnterBackground()
        passcode.withLock { $0 = .set }
        await controller.sceneDidBecomeActive()
        #expect(controller.state == .unlocked)
        #expect(await vault.openCount == 1)
    }

    @Test func returningDoesNotRetryAScreenThatNeedsADecision() async {
        let vault = FakeVault([.failure(.vaultKeyMissing)])
        let controller = makeController(vault)
        await controller.sceneDidBecomeActive()
        controller.sceneDidEnterBackground()
        await controller.sceneDidBecomeActive()
        #expect(controller.state == .recovery(.keyMissing))
        #expect(await vault.openCount == 1)
    }

    @Test func debugLogRecordsEachAttemptWithoutIdsOrValues() async throws {
        let vault = FakeVault([Self.unavailable(-128), .success(OpenReport())])
        let controller = makeController(vault)
        await controller.sceneDidBecomeActive()
        await controller.unlock()
        await controller.protectedDataWillBecomeUnavailable()
        let log = controller.attemptLog
        try #require(log.count == 3)
        #expect(log[0].contains("-128") && log[0].contains("lockCover"))
        #expect(log[1].contains("opened") && log[1].contains("unlocked"))
        #expect(log[2].contains("phone locked"))
    }

    @Test func phoneLockingDuringThePromptIsACancelWithoutARetry() async {
        // Check 7 on the iPhone: the phone locks while the prompt is up, and the interrupted
        // read returns -25293 before the app has left the foreground.
        let vault = FakeVault(
            [Self.unavailable(-25293), Self.unavailable(-25308)], gated: true, onlyFirstGated: true)
        let controller = makeController(vault)
        let opening = Task { await controller.sceneDidBecomeActive() }
        #expect(await vault.waitUntilOpening())
        await controller.protectedDataWillBecomeUnavailable()
        await vault.release()
        await opening.value
        #expect(controller.state == .locked)
        #expect(await vault.openCount == 1)  // no second prompt against a locked phone
    }

    @Test func aLockDuringASuccessfulOpenWins() async {
        // Face ID succeeds just as the phone locks: the open finishes after the lock.
        let vault = FakeVault([.success(OpenReport())], gated: true, onlyFirstGated: true)
        let controller = makeController(vault)
        let opening = Task { await controller.sceneDidBecomeActive() }
        #expect(await vault.waitUntilOpening())
        await controller.lock()
        await vault.release()
        await opening.value
        #expect(controller.state == .locked)
        #expect(controller.contentHidden)
        #expect(await vault.lockCount == 2)  // locked again, after the open finished
    }

    @Test func noticesFromOpening() async {
        var report = OpenReport()
        report.repairWaitingForSpace = true
        let controller = makeController(FakeVault([.success(report)]))
        await controller.sceneDidBecomeActive()
        #expect(controller.state == .unlocked)
        #expect(controller.notices == [.repairWaitingForSpace])
    }
}

@MainActor
@Suite("Notices")
struct NoticeTests {
    func unlocked() async -> LockController {
        let controller = LockController(
            vault: FakeVault([]), clock: FixedClock(), autoLock: .oneMinute, passcode: { .set },
            vaultExists: { true }, protectedDataAvailable: { true })
        await controller.sceneDidBecomeActive()
        return controller
    }

    /// Locking removes every screen and drops a scan in progress; after unlocking the user is told.
    @Test func aScanDroppedByTheLockIsToldAfterUnlocking() async {
        let controller = await unlocked()
        controller.scanStarted(.camera)
        await controller.lock()
        await controller.unlock()
        #expect(controller.notices.contains(.scanDropped))
        #expect(!controller.notices.contains(.photosDropped))
    }

    /// Photos added with Tambah are dropped too, but their originals are still in Photos, so the notice
    /// says that instead of asking for a new scan.
    @Test func lockAfterPhotosTellsPhotosDropped() async {
        let controller = await unlocked()
        controller.scanStarted(.photos)
        await controller.lock()
        await controller.unlock()
        #expect(controller.notices.contains(.photosDropped))
        #expect(!controller.notices.contains(.scanDropped))
    }

    @Test func aScanThatEndedBeforeTheLockIsntMentioned() async {
        let controller = await unlocked()
        controller.scanStarted(.photos)
        controller.scanEnded()
        await controller.lock()
        await controller.unlock()
        #expect(!controller.notices.contains(.scanDropped))
    }

    @Test func theDroppedScanIsToldOnce() async {
        let controller = await unlocked()
        controller.scanStarted(.camera)
        await controller.lock()
        await controller.unlock()
        controller.dismiss(.scanDropped)
        await controller.lock()
        await controller.unlock()
        #expect(!controller.notices.contains(.scanDropped))
    }

    /// NoticeList only shows what's in its order, so a notice missing there would never appear.
    @Test func everyNoticeIsListed() {
        #expect(Set(NoticeList.order) == Set(VaultNotice.allCases))
    }

    @Test func aNoticeIsShownUntilDismissed() async {
        var report = OpenReport()
        report.newestChangeMayBeLost = true
        report.repairWaitingForSpace = true
        let lock = LockController(
            vault: FakeVault([.success(report)]), clock: FixedClock(), passcode: { .set },
            vaultExists: { true }, protectedDataAvailable: { true })
        await lock.unlock()
        #expect(lock.notices == [.newestChangeMayBeLost, .repairWaitingForSpace])
        lock.dismiss(.newestChangeMayBeLost)
        #expect(lock.notices == [.repairWaitingForSpace])
    }
}
