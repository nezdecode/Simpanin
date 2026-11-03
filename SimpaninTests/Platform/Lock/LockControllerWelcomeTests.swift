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
    let clock = FixedClock()
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
        clock.advance(by: 600)
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
}
