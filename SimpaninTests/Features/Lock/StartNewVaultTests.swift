//
//  StartNewVaultTests.swift
//  SimpaninTests
//
//  Created by Inez Amanda on 14/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import Testing

@testable import Simpanin
@testable import VaultCore

@MainActor
@Suite("Mulai vault baru")
struct StartNewVaultTests {
    let quarantineFolder = URL(filePath: "/Support/Quarantine", directoryHint: .isDirectory)

    func makeLock(_ vault: FakeVault) -> LockController {
        LockController(
            vault: vault, clock: FixedClock(), passcode: { .set }, vaultExists: { true }, vaultIsEmpty: { false },
            protectedDataAvailable: { true })
    }

    @Test(arguments: ["MULAI BARU", "mulai baru", "  Mulai Baru "])
    func typedConfirmationMatches(_ text: String) {
        #expect(StartNewVaultModel.matches(text))
    }

    @Test(arguments: ["", "MULAI", "mulaibaru", "MULAI BARU!", "ya"])
    func otherTextDoesNotMatch(_ text: String) {
        #expect(!StartNewVaultModel.matches(text))
    }

    @Test func confirmingQuarantinesThenOpens() async {
        let quarantine = FakeQuarantine()
        let vault = FakeVault([.failure(.vaultKeyMissing), .success(OpenReport())])
        let lock = makeLock(vault)
        await lock.unlock()
        #expect(lock.state == .recovery(.keyMissing))

        let model = StartNewVaultModel(store: quarantine, quarantineFolder: quarantineFolder, lock: lock)
        model.typed = "MULAI BARU"
        await model.confirm()
        #expect(await quarantine.quarantinedTo == [quarantineFolder])
        #expect(lock.state == .unlocked)
    }

    /// The move leaves an empty folder, which on its own would show the welcome.
    @Test func startingANewVaultOpensWithoutTheWelcome() async {
        let conditions = LaunchConditions()
        conditions.vaultCreated()
        let vault = FakeVault([.failure(.vaultKeyMissing), .success(OpenReport())])
        let lock = LockController(
            vault: vault, clock: FixedClock(), passcode: { conditions.passcode },
            vaultExists: { conditions.headerExists }, vaultIsEmpty: { try conditions.isEmpty() },
            protectedDataAvailable: { true })
        await lock.unlock()
        #expect(lock.state == .recovery(.keyMissing))

        let model = StartNewVaultModel(store: FakeQuarantine(), quarantineFolder: quarantineFolder, lock: lock)
        model.typed = "MULAI BARU"
        conditions.headerExists = false
        conditions.empty = true
        await model.confirm()
        #expect(lock.state == .unlocked)
        #expect(await vault.openCount == 2)
    }

    /// The user already chose a new vault, so the recovery screen stays while it's created, never the welcome.
    @Test func startingANewVaultNeverShowsTheWelcomeWhileCreating() async {
        let conditions = LaunchConditions()
        conditions.vaultCreated()
        let vault = FakeVault([.failure(.vaultKeyMissing), .success(OpenReport())])
        let lock = LockController(
            vault: vault, clock: FixedClock(), passcode: { conditions.passcode },
            vaultExists: { conditions.headerExists }, vaultIsEmpty: { try conditions.isEmpty() },
            protectedDataAvailable: { true })
        await lock.unlock()
        let model = StartNewVaultModel(store: FakeQuarantine(), quarantineFolder: quarantineFolder, lock: lock)
        model.typed = "MULAI BARU"
        conditions.headerExists = false
        conditions.empty = true
        await vault.gateNextOpen()
        let confirming = Task { await model.confirm() }
        #expect(await vault.waitUntilOpening())
        #expect(CoverContent(lock) != .welcome)
        await vault.release()
        await confirming.value
        #expect(lock.state == .unlocked)
    }

    @Test func aFirstFailureAfterStartingANewVaultShowsItsScreen() async {
        let conditions = LaunchConditions()
        conditions.vaultCreated()
        let vault = FakeVault([.failure(.vaultKeyMissing), .failure(.vaultKeyUnavailable(status: -50))])
        let lock = LockController(
            vault: vault, clock: FixedClock(), passcode: { conditions.passcode },
            vaultExists: { conditions.headerExists }, vaultIsEmpty: { try conditions.isEmpty() },
            protectedDataAvailable: { true })
        await lock.unlock()
        let model = StartNewVaultModel(store: FakeQuarantine(), quarantineFolder: quarantineFolder, lock: lock)
        model.typed = "MULAI BARU"
        conditions.headerExists = false
        conditions.empty = true
        await model.confirm()
        #expect(lock.state == .recovery(.cannotOpenNow))
        #expect(await vault.openCount == 2)
    }

    @Test func nothingHappensWithoutTheWord() async {
        let quarantine = FakeQuarantine()
        let vault = FakeVault([.failure(.vaultUnreadable)])
        let lock = makeLock(vault)
        await lock.unlock()
        let model = StartNewVaultModel(store: quarantine, quarantineFolder: quarantineFolder, lock: lock)
        model.typed = "mulai"
        await model.confirm()
        #expect(await quarantine.quarantinedTo.isEmpty)
        #expect(await vault.openCount == 1)
    }

    @Test func aFailedMoveKeepsTheScreenAndSaysSo() async {
        let quarantine = FakeQuarantine()
        await quarantine.setFailure(.fileUnavailable)
        let vault = FakeVault([.failure(.vaultUnreadable)])
        let lock = makeLock(vault)
        await lock.unlock()
        let model = StartNewVaultModel(store: quarantine, quarantineFolder: quarantineFolder, lock: lock)
        model.typed = "MULAI BARU"
        await model.confirm()
        #expect(model.failed)
        #expect(lock.state == .recovery(.vaultUnreadable))
        #expect(await vault.openCount == 1)
    }
}
