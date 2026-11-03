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

/// What the phone looks like to the lock, changed by the test as it goes.
@MainActor
final class LaunchConditions {
    var passcode = PasscodeState.set
    var headerExists = false
    var empty = true
    var emptyCheckFails = false
    var protectedData = true
    private(set) var emptyChecks = 0

    func isEmpty() throws -> Bool {
        emptyChecks += 1
        if emptyCheckFails { throw CocoaError(.fileReadNoPermission) }
        return empty
    }

    /// After `open()` has created the vault.
    func vaultCreated() {
        headerExists = true
        empty = false
    }
}

/// The welcome screen: shown while nothing on the phone could be a document, before the vault exists.
@MainActor
@Suite("Lock controller: welcome")
struct LockControllerWelcomeTests {
    let clock = FixedClock()
    let conditions = LaunchConditions()

    func makeController(_ vault: FakeVault) -> LockController {
        let conditions = conditions
        return LockController(
            vault: vault, clock: clock, autoLock: .oneMinute, passcode: { conditions.passcode },
            vaultExists: { conditions.headerExists }, vaultIsEmpty: { try conditions.isEmpty() },
            protectedDataAvailable: { conditions.protectedData })
    }

    /// The welcome is up, nothing opened yet.
    func welcome(_ vault: FakeVault) async -> LockController {
        let controller = makeController(vault)
        await controller.sceneDidBecomeActive()
        #expect(controller.state == .noVault)
        return controller
    }

    // MARK: When it shows

    @Test func firstLaunchShowsTheWelcomeWithoutOpening() async {
        let vault = FakeVault([])
        let controller = makeController(vault)
        await controller.sceneDidBecomeActive()
        #expect(controller.state == .noVault)
        #expect(controller.contentHidden)
        #expect(await vault.openCount == 0)
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

    // MARK: Creating the vault

    @Test func creatingTheVaultChecksThePasscodeAgain() async {
        let vault = FakeVault([])
        let controller = await welcome(vault)
        conditions.passcode = .notSet
        await controller.createVault(then: .camera)
        #expect(controller.state == .recovery(.passcodeNeeded))
        #expect(controller.takePendingScan() == nil)
        #expect(await vault.openCount == 0)
    }

    @Test(arguments: [ScanSource.camera, .photos])
    func creatingTheVaultOpensOnceAndKeepsTheChosenScan(_ source: ScanSource) async {
        let vault = FakeVault([])
        let controller = await welcome(vault)
        await controller.createVault(then: source)
        #expect(controller.state == .unlocked)
        #expect(controller.takePendingScan() == source)
        #expect(await vault.openCount == 1)
    }

    @Test func nantiSajaCreatesTheVaultWithNoScan() async {
        let vault = FakeVault([])
        let controller = await welcome(vault)
        await controller.createVault(then: nil)
        #expect(controller.state == .unlocked)
        #expect(controller.takePendingScan() == nil)
        #expect(await vault.openCount == 1)
    }

    @Test func aSecondTapWhileCreatingOpensOnce() async {
        let vault = FakeVault([])
        let controller = await welcome(vault)
        await vault.gateNextOpen()
        let creating = Task { await controller.createVault(then: .camera) }
        #expect(await vault.waitUntilOpening())
        await controller.createVault(then: .photos)
        await vault.release()
        await creating.value
        #expect(controller.state == .unlocked)
        #expect(controller.takePendingScan() == .camera)
        #expect(await vault.openCount == 1)
    }

    @Test func aLockWhileCreatingDropsTheChosenScanWithoutANotice() async {
        let vault = FakeVault([])
        let controller = await welcome(vault)
        await vault.gateNextOpen()
        let creating = Task { await controller.createVault(then: .camera) }
        #expect(await vault.waitUntilOpening())
        await controller.protectedDataWillBecomeUnavailable()
        conditions.vaultCreated()
        await vault.release()
        await creating.value
        #expect(controller.state == .locked)

        controller.sceneDidEnterBackground()
        await controller.sceneDidBecomeActive()
        #expect(controller.state == .unlocked)
        #expect(controller.notices.isEmpty)
        #expect(controller.takePendingScan() == nil)
    }

    @Test func aLockBeforeTheScanIsTakenDropsIt() async {
        let vault = FakeVault([])
        let controller = await welcome(vault)
        await controller.createVault(then: .photos)
        conditions.vaultCreated()
        await controller.lock()
        await controller.unlock()
        #expect(controller.state == .unlocked)
        #expect(controller.notices.isEmpty)
        #expect(controller.takePendingScan() == nil)
    }

    @Test func theChosenScanIsTakenOnce() async {
        let controller = await welcome(FakeVault([]))
        await controller.createVault(then: .camera)
        #expect(controller.takePendingScan() == .camera)
        #expect(controller.takePendingScan() == nil)
    }

    @Test func storageFullWhileCreatingRetriesToTheWelcome() async {
        let vault = FakeVault([.failure(.storageFull)])
        let controller = await welcome(vault)
        await controller.createVault(then: .camera)
        #expect(controller.state == .recovery(.storageFullOnOpen))
        #expect(controller.takePendingScan() == nil)

        // "Coba lagi" on that screen.
        await controller.unlock()
        #expect(controller.state == .noVault)
        #expect(await vault.openCount == 1)
    }

    @Test func aCancelledCreateLeavesTheWelcome() async {
        let vault = FakeVault([.failure(.locked)])
        let controller = await welcome(vault)
        await controller.createVault(then: .camera)
        #expect(controller.state == .noVault)
        #expect(controller.takePendingScan() == nil)
    }

    @Test func anOtherErrorWhileCreatingShowsRecovery() async {
        let vault = FakeVault([.failure(.authenticationFailed)])
        let controller = await welcome(vault)
        await controller.createVault(then: .photos)
        #expect(controller.state == .recovery(.cannotOpenNow))
        #expect(controller.takePendingScan() == nil)
    }
}
