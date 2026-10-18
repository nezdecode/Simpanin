//
//  RecoveryMapping.swift
//  Simpanin
//
//  Created by Inez Amanda on 14/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import Security
import VaultCore

/// A screen from the design doc's recovery table.
nonisolated enum RecoveryScreen: Equatable, Sendable {
    /// No passcode on the device yet: "Simpanin butuh passcode HP untuk mengunci dokumenmu."
    case passcodeNeeded
    /// The passcode was turned off after the vault existed: "Pasang passcode lagi untuk membuka vault."
    case passcodeTurnedOff
    /// "Buka kunci HP, lalu coba lagi." Never offers a new vault.
    case unlockPhoneAndRetry
    /// "Vault tidak bisa dibuka sekarang. Coba lagi nanti." Never offers a new vault.
    case cannotOpenNow
    /// "Kunci vault tidak ditemukan. ..." with "Mulai vault baru".
    case keyMissing
    /// "Vault tidak bisa dibuka." with "Mulai vault baru".
    case vaultUnreadable
    /// "Versi Simpanin ini terlalu lama untuk vault ini. Perbarui app." Never quarantines.
    case updateApp
    /// "Penyimpanan HP penuh. Kosongkan ruang untuk mulai memakai Simpanin."
    case storageFullOnOpen
    /// "Penyimpanan HP penuh. Perubahan belum tersimpan, data lama aman."
    case storageFullOnSave
    /// Any other failed save, except a lock: "Perubahan belum tersimpan. Coba lagi."
    case saveFailed
}

/// What the lock screen does after an attempt to open the vault.
nonisolated enum LockOutcome: Equatable, Sendable {
    case unlocked(notices: Set<VaultNotice>)
    /// A cancel: the lock cover stays, with an "Buka" button, and no error is shown.
    case lockCover
    /// Show the normal prompt again.
    case promptAgain
    case recovery(RecoveryScreen)
}

/// The design doc's recovery screens table as a pure function, so every row is tested.
nonisolated enum RecoveryMapping {
    /// "Any other status" prompts again once; the second failure in a row shows a screen.
    static let failuresBeforeGivingUp = 2

    /// Checked before `open()`, so no prompt appears on a phone without a passcode.
    static func beforeOpening(passcode: PasscodeState, vaultExists: Bool) -> RecoveryScreen? {
        guard passcode == .notSet else { return nil }
        return vaultExists ? .passcodeTurnedOff : .passcodeNeeded
    }

    /// - Parameters:
    ///   - failuresInARow: earlier "any other status" failures, not counting this one.
    ///   - leftForegroundDuringPrompt: the app went to the background while the prompt was up.
    ///     The system then cancels the prompt and the Keychain reports -25293, not -128.
    static func outcome(
        of result: Result<OpenReport, any Error>, passcode: PasscodeState, failuresInARow: Int,
        leftForegroundDuringPrompt: Bool
    ) -> LockOutcome {
        switch result {
        case .success(let report):
            .unlocked(notices: notices(report))
        case .failure(.vaultKeyUnavailable(let status) as VaultError):
            keyUnavailable(
                status, passcode: passcode, failuresInARow: failuresInARow,
                leftForegroundDuringPrompt: leftForegroundDuringPrompt)
        case .failure(let error as VaultError):
            outcome(of: error)
        case .failure:
            .recovery(.cannotOpenNow)
        }
    }

    private static func keyUnavailable(
        _ status: Int32?, passcode: PasscodeState, failuresInARow: Int, leftForegroundDuringPrompt: Bool
    ) -> LockOutcome {
        switch status {
        case errSecUserCanceled:
            .lockCover
        case errSecAuthFailed where leftForegroundDuringPrompt:
            .lockCover
        case errSecAuthFailed where passcode == .notSet:
            .recovery(.passcodeTurnedOff)
        case errSecInteractionNotAllowed:
            .recovery(.unlockPhoneAndRetry)
        default:
            failuresInARow + 1 >= failuresBeforeGivingUp ? .recovery(.cannotOpenNow) : .promptAgain
        }
    }

    private static func outcome(of error: VaultError) -> LockOutcome {
        switch error {
        case .locked: .lockCover
        case .fileUnavailable: .recovery(.unlockPhoneAndRetry)
        case .vaultKeyMissing: .recovery(.keyMissing)
        case .vaultUnreadable, .vaultHeaderMissing, .corruptFile: .recovery(.vaultUnreadable)
        case .unsupportedVersion: .recovery(.updateApp)
        case .storageFull: .recovery(.storageFullOnOpen)
        default: .recovery(.cannotOpenNow)
        }
    }

    /// A save never fails quietly. A lock is the one exception: the cover already explains it.
    static func screen(forSaveError error: any Error) -> RecoveryScreen? {
        switch error as? VaultError {
        case .storageFull: .storageFullOnSave
        case .locked: nil
        default: .saveFailed
        }
    }

    private static func notices(_ report: OpenReport) -> Set<VaultNotice> {
        var notices: Set<VaultNotice> = []
        if report.newestChangeMayBeLost { notices.insert(.newestChangeMayBeLost) }
        if report.recoveredFromPages { notices.insert(.recoveredFromPages) }
        if report.repairWaitingForSpace { notices.insert(.repairWaitingForSpace) }
        return notices
    }
}
