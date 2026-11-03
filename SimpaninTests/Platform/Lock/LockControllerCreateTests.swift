//
//  LockControllerCreateTests.swift
//  SimpaninTests
//
//  Created by Inez Amanda on 4/11/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import Testing

@testable import Simpanin
@testable import VaultCore

/// Creating the vault from the welcome: the passcode checked again, the chosen scan handed over once, and
/// what a lock or an error leaves behind.
@MainActor
@Suite("Lock controller: creating the vault")
struct LockControllerCreateTests {
    let clock = FixedClock()
    let conditions = LaunchConditions()

    func welcome(_ vault: FakeVault) async -> LockController { await conditions.welcome(vault, clock: clock) }

    /// A lock that wins over a create that never wrote anything leaves the welcome too.
    @Test func aLockDuringACreateThatLeftNothingKeepsTheWelcome() async {
        let vault = FakeVault([])
        let controller = await welcome(vault)
        await vault.gateNextOpen()
        let creating = Task { await controller.createVault(then: .camera) }
        #expect(await vault.waitUntilOpening())
        await controller.protectedDataWillBecomeUnavailable()
        #expect(controller.state == .noVault)
        await vault.release()
        await creating.value
        #expect(controller.state == .noVault)
        #expect(controller.takePendingScan() == nil)
    }

    /// Creating shows no prompt, so prompting again would only land back on the welcome and hide the error.
    @Test func aFirstFailureWhileCreatingShowsItsScreen() async {
        let vault = FakeVault([.failure(.vaultKeyUnavailable(status: -50))])
        let controller = await welcome(vault)
        await controller.createVault(then: .camera)
        #expect(controller.state == .recovery(.cannotOpenNow))
        #expect(await vault.openCount == 1)
        #expect(controller.takePendingScan() == nil)
    }

    @Test func aLockedPhoneWhileCreatingShowsItsOwnScreen() async {
        let vault = FakeVault([.failure(.vaultKeyUnavailable(status: -25308))])
        let controller = await welcome(vault)
        await controller.createVault(then: nil)
        #expect(controller.state == .recovery(.unlockPhoneAndRetry))
    }

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

    @Test func theWelcomeStaysUpWhileTheVaultIsCreated() async {
        let vault = FakeVault([])
        let controller = await welcome(vault)
        await vault.gateNextOpen()
        let creating = Task { await controller.createVault(then: .camera) }
        #expect(await vault.waitUntilOpening())
        #expect(controller.isCreatingVault)
        await vault.release()
        await creating.value
        #expect(!controller.isCreatingVault)
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
