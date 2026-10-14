//
//  ScreenLogicTests.swift
//  SimpaninTests
//
//  Created by Inez Amanda on 15/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import LocalAuthentication
import Testing
import VaultCore

@testable import Simpanin

/// The small decisions behind the restyled screens.
@Suite("Screen logic")
struct ScreenLogicTests {
    // MARK: The lock cover's button follows how the phone unlocks

    @Test func unlockMethod() {
        #expect(UnlockMethod.from(biometryType: .faceID, canUseBiometrics: true, errorCode: nil) == .faceID)
        #expect(UnlockMethod.from(biometryType: .touchID, canUseBiometrics: true, errorCode: nil) == .touchID)
        // No face enrolled: the passcode is what unlocks.
        let notEnrolled = LAError.Code.biometryNotEnrolled.rawValue
        #expect(UnlockMethod.from(biometryType: .faceID, canUseBiometrics: false, errorCode: notEnrolled) == .passcode)
        // Face ID exists but the user turned it off for Simpanin.
        let notAvailable = LAError.Code.biometryNotAvailable.rawValue
        #expect(
            UnlockMethod.from(biometryType: .faceID, canUseBiometrics: false, errorCode: notAvailable)
                == .faceIDTurnedOff)
        #expect(UnlockMethod.from(biometryType: .none, canUseBiometrics: false, errorCode: nil) == .passcode)
    }

    @Test func unlockCaptions() {
        #expect(String(localized: UnlockMethod.faceID.caption) == "Pakai Face ID atau passcode HP")
        #expect(String(localized: UnlockMethod.touchID.caption) == "Pakai Touch ID atau passcode HP")
        #expect(String(localized: UnlockMethod.passcode.caption) == "Pakai passcode HP")
        #expect(String(localized: UnlockMethod.faceIDTurnedOff.caption) == "Pakai passcode HP")
    }

    // MARK: Data lama, named after when the vault was moved aside (folder names are UTC)

    let jakarta = TimeZone(identifier: "Asia/Jakarta")!

    @Test func oldVaultTitleAndDetail() throws {
        let moved = try #require(OldVaultText.movedAt(folderName: "20261014-021200"))
        #expect(String(localized: OldVaultText.title(moved, timeZone: jakarta)) == "Vault lama, 14 Okt 2026")
        #expect(
            String(localized: OldVaultText.detail(moved, sizeInBytes: 48_000_000, timeZone: jakarta))
                .hasSuffix("dipindahkan pukul 09.12"))
        // A second vault moved in the same second gets "-2"; the time still reads.
        #expect(OldVaultText.movedAt(folderName: "20261014-021200-2") == moved)
        #expect(OldVaultText.movedAt(folderName: "not-a-date") == nil)
    }

    // MARK: Baru dihapus counts down to the purge

    @Test func daysUntilPurge() {
        let deleted = Date(timeIntervalSince1970: 1_790_000_000)
        let day: TimeInterval = 86_400
        #expect(PurgeCountdown.daysLeft(deletedAt: deleted, now: deleted) == 30)
        #expect(PurgeCountdown.daysLeft(deletedAt: deleted, now: deleted + 7 * day) == 23)
        #expect(PurgeCountdown.daysLeft(deletedAt: deleted, now: deleted + 7 * day + 60) == 23)
        #expect(PurgeCountdown.daysLeft(deletedAt: deleted, now: deleted + 30 * day - 60) == 1)
        #expect(PurgeCountdown.daysLeft(deletedAt: deleted, now: deleted + 31 * day) == 0)
        #expect(String(localized: PurgeCountdown.text(daysLeft: 23)) == "Dihapus permanen dalam 23 hari")
        #expect(String(localized: PurgeCountdown.text(daysLeft: 0)) == "Dihapus permanen hari ini")
    }
}

// MARK: - Kunci otomatis

@MainActor
@Suite("Auto-lock setting")
struct AutoLockTests {
    func defaults() -> UserDefaults {
        let name = "AutoLockTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func choicesAndDefault() {
        #expect(AutoLock.allCases.map(\.seconds) == [0, 60, 300])
        #expect(AutoLock.stored(in: defaults()) == .oneMinute)
        #expect(String(localized: AutoLock.immediately.title) == "Langsung")
        #expect(String(localized: AutoLock.oneMinute.title) == "Setelah 1 menit")
        #expect(String(localized: AutoLock.fiveMinutes.title) == "Setelah 5 menit")
    }

    @Test func choiceIsKept() {
        let defaults = defaults()
        AutoLock.fiveMinutes.store(in: defaults)
        #expect(AutoLock.stored(in: defaults) == .fiveMinutes)
    }

    @Test func immediatelyRelocksOnAnyReturn() async {
        let clock = FixedClock()
        let vault = FakeVault([])
        let controller = LockController(
            vault: vault, clock: clock, passcode: { .set }, vaultExists: { true }, protectedDataAvailable: { true })
        await controller.sceneDidBecomeActive()
        controller.relockTimeout = AutoLock.immediately.seconds
        controller.sceneDidEnterBackground()
        clock.advance(by: 1)
        await controller.sceneDidBecomeActive()
        #expect(await vault.lockCount == 1)
        #expect(await vault.openCount == 2)
    }
}
