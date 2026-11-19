//
//  LockControllerWelcomeTests.swift
//  SimpaninTests
//
//  Created by Inez Amanda on 3/11/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import Testing

@testable import Simpanin
@testable import VaultCore

/// The welcome screen: shown while nothing on the phone could be a document, before the vault exists.
@MainActor
@Suite("Lock controller: welcome")
struct LockControllerWelcomeTests {
    let clock = ManualClock()
    let conditions = LaunchConditions()

    func makeController(_ vault: FakeVault) -> LockController { conditions.makeController(vault, clock: clock) }

    func welcome(_ vault: FakeVault) async -> LockController { await conditions.welcome(vault, clock: clock) }

    // MARK: When it shows

    @Test func firstLaunchShowsTheWelcomeWithoutOpening() async {
        let vault = FakeVault([])
        let controller = makeController(vault)
        await controller.sceneDidBecomeActive()
        #expect(controller.state == .noVault)
        #expect(controller.contentHidden)
        #expect(await vault.openCount == 0)
    }

    /// Before the scene is active, so the first frame draws the welcome, never the lock cover.
    @Test func theWelcomeShowsFromTheFirstFrame() {
        #expect(makeController(FakeVault([])).state == .noVault)
        conditions.protectedData = false
        #expect(makeController(FakeVault([])).state == .locked)
        conditions.protectedData = true
        conditions.passcode = .notSet
        #expect(makeController(FakeVault([])).state == .locked)
    }

    @Test func returningDuringTheWelcomeNeverOpens() async {
        let vault = FakeVault([])
        let controller = await welcome(vault)
        controller.sceneDidBecomeInactive()
        controller.sceneDidEnterBackground()
        clock.advance(by: .seconds(600))
        await controller.sceneDidBecomeActive()
        #expect(controller.state == .noVault)
        #expect(await vault.openCount == 0)
    }

    @Test func phoneLockingDuringTheWelcomeShowsItAgainWithoutAPrompt() async {
        let vault = FakeVault([])
        let controller = await welcome(vault)
        await controller.protectedDataWillBecomeUnavailable()
        controller.sceneDidEnterBackground()
        await controller.sceneDidBecomeActive()
        #expect(controller.state == .noVault)
        #expect(await vault.openCount == 0)
    }

    /// Nothing is open, so a lock leaves the welcome, never the lock screen on a phone with no vault.
    @Test func aLockDuringTheWelcomeKeepsIt() async {
        let vault = FakeVault([])
        let controller = await welcome(vault)
        await controller.protectedDataWillBecomeUnavailable()
        #expect(controller.state == .noVault)
        await controller.lock()
        #expect(controller.state == .noVault)
    }

    /// The welcome promises a passcode lock, so a return checks the passcode is still there.
    @Test func turningThePasscodeOffDuringTheWelcomeShowsThePasscodeScreenOnReturn() async {
        let vault = FakeVault([])
        let controller = await welcome(vault)
        await controller.protectedDataWillBecomeUnavailable()
        conditions.passcode = .notSet
        controller.sceneDidEnterBackground()
        await controller.sceneDidBecomeActive()
        #expect(controller.state == .recovery(.passcodeNeeded))
        #expect(await vault.openCount == 0)
    }

    @Test func firstLaunchWithoutAPasscodeShowsThePasscodeScreen() async {
        conditions.passcode = .notSet
        let vault = FakeVault([])
        let controller = makeController(vault)
        await controller.sceneDidBecomeActive()
        #expect(controller.state == .recovery(.passcodeNeeded))
        #expect(await vault.openCount == 0)
    }

    @Test func turningThePasscodeOnLeadsToTheWelcome() async {
        conditions.passcode = .notSet
        let vault = FakeVault([])
        let controller = makeController(vault)
        await controller.sceneDidBecomeActive()
        controller.sceneDidEnterBackground()
        conditions.passcode = .set
        await controller.sceneDidBecomeActive()
        #expect(controller.state == .noVault)
        #expect(await vault.openCount == 0)
    }

    @Test func anUnknownPasscodeStateShowsTheWelcome() async {
        conditions.passcode = .unknown(code: -1)
        _ = await welcome(FakeVault([]))
    }

    @Test func leftoverVaultFilesOpenAndNeverShowTheWelcome() async {
        conditions.empty = false
        let vault = FakeVault([.failure(.vaultHeaderMissing)])
        let controller = makeController(vault)
        await controller.sceneDidBecomeActive()
        #expect(controller.state == .recovery(.vaultUnreadable))
        #expect(await vault.openCount == 1)
    }

    @Test func anUnreadableVaultFolderNeverShowsTheWelcome() async {
        conditions.emptyCheckFails = true
        let vault = FakeVault([.failure(.fileUnavailable)])
        let controller = makeController(vault)
        await controller.sceneDidBecomeActive()
        #expect(controller.state == .recovery(.unlockPhoneAndRetry))
        #expect(await vault.openCount == 1)
    }

    @Test func aVaultWithoutItsKeyGoesToRecoveryNotTheWelcome() async {
        conditions.vaultCreated()
        let vault = FakeVault([.failure(.vaultKeyMissing)])
        let controller = makeController(vault)
        await controller.sceneDidBecomeActive()
        #expect(controller.state == .recovery(.keyMissing))
    }

    @Test func theWelcomeWaitsForProtectedData() async {
        conditions.protectedData = false
        let vault = FakeVault([])
        let controller = makeController(vault)
        await controller.sceneDidBecomeActive()
        #expect(controller.state == .locked)
        #expect(conditions.emptyChecks == 0)
        #expect(await vault.openCount == 0)
    }

    @Test func theWelcomeShowsOnceProtectedDataArrives() async {
        conditions.protectedData = false
        let vault = FakeVault([])
        let controller = makeController(vault)
        await controller.sceneDidBecomeActive()
        conditions.protectedData = true
        await controller.protectedDataDidBecomeAvailable()
        #expect(controller.state == .noVault)
        #expect(await vault.openCount == 0)
    }

    /// Two taps on the welcome before it turns its buttons off. The first create fails; the second tap, which waited
    /// for it, finds the error screen, not the welcome it was tapped on, so it doesn't create again.
    @Test(.timeLimit(.minutes(1)))
    func aSecondWelcomeTapAfterAFailedCreateDoesNotCreateAgain() async {
        let vault = FakeVault([.failure(.storageFull)])
        let controller = await welcome(vault)
        await vault.gateNextOpen()
        let first = Task { await controller.createVault(then: .camera) }
        #expect(await vault.waitUntilOpening())
        let second = Task { await controller.createVault(then: .camera) }
        try? await Task.sleep(for: .milliseconds(100))
        await vault.release()
        await first.value
        await second.value
        #expect(controller.state == .recovery(.storageFullOnOpen))
        #expect(await vault.openCount == 1)
    }

    // MARK: A tap behind a phone lock

    /// A phone lock keeps the welcome, so the tap that waited for it still finds its screen. It creates nothing, and
    /// the welcome works again once the phone is unlocked.
    @Test(.timeLimit(.minutes(1)))
    func aWelcomeTapThatWaitedOutAPhoneLockCreatesNothing() async {
        let vault = FakeVault([])
        let controller = await welcome(vault)
        await vault.gateNextLock()
        conditions.protectedData = false
        let locking = Task { await controller.protectedDataWillBecomeUnavailable() }
        #expect(await vault.waitUntilLocking())
        let creating = Task { await controller.createVault(then: .camera) }
        // Long enough for the create to read its screen and start waiting before the lock lands.
        try? await Task.sleep(for: .milliseconds(100))
        await vault.releaseLock()
        await locking.value
        await creating.value
        #expect(controller.state == .noVault)
        #expect(await vault.openCount == 0)

        conditions.protectedData = true
        await controller.sceneDidBecomeActive()
        #expect(controller.state == .noVault)
        await controller.createVault(then: .camera)
        #expect(controller.state == .unlocked)
        #expect(await vault.openCount == 1)
        #expect(controller.takePendingScan() == .camera)
    }

    /// iOS posts the phone lock before the files lock, so protected data can still read as there.
    @Test(.timeLimit(.minutes(1)))
    func aWelcomeTapIsDroppedWhenAPhoneLockLandsBeforeFilesLock() async {
        let vault = FakeVault([])
        let controller = await welcome(vault)
        await vault.gateNextLock()
        let locking = Task { await controller.protectedDataWillBecomeUnavailable() }
        #expect(await vault.waitUntilLocking())
        let creating = Task { await controller.createVault(then: .camera) }
        try? await Task.sleep(for: .milliseconds(100))
        await vault.releaseLock()
        await locking.value
        await creating.value
        #expect(controller.state == .noVault)
        #expect(await vault.openCount == 0)
    }

    @Test func aWelcomeTapWithoutProtectedDataCreatesNothing() async {
        let vault = FakeVault([])
        let controller = await welcome(vault)
        conditions.protectedData = false
        await controller.createVault(then: .camera)
        #expect(controller.state == .noVault)
        #expect(await vault.openCount == 0)
    }
}
