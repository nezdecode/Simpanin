//
//  RecoveryMappingTests.swift
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

/// One test per row of the recovery screens table. The statuses are the ones
/// the device checks returned on an iPhone (iOS 26.6.1, 14 Oct 2026).
@Suite("Recovery screens")
struct RecoveryMappingTests {
    func outcome(
        _ error: any Error, passcode: PasscodeState = .set, failuresInARow: Int = 0, leftForeground: Bool = false
    ) -> LockOutcome {
        RecoveryMapping.outcome(
            of: .failure(error), passcode: passcode, failuresInARow: failuresInARow,
            leftForegroundDuringPrompt: leftForeground)
    }

    func opened(_ report: OpenReport) -> LockOutcome {
        RecoveryMapping.outcome(
            of: .success(report), passcode: .set, failuresInARow: 0, leftForegroundDuringPrompt: false)
    }

    // MARK: Before any prompt

    @Test func noPasscodeIsCheckedBeforeOpening() {
        #expect(RecoveryMapping.beforeOpening(passcode: .notSet, vaultExists: false) == .passcodeNeeded)
        #expect(RecoveryMapping.beforeOpening(passcode: .notSet, vaultExists: true) == .passcodeTurnedOff)
        #expect(RecoveryMapping.beforeOpening(passcode: .set, vaultExists: true) == nil)
        // An unclear answer doesn't block: the Keychain still decides.
        #expect(RecoveryMapping.beforeOpening(passcode: .unknown(code: -8), vaultExists: true) == nil)
    }

    // MARK: Opened

    @Test func openedNormallyHasNoNotice() {
        #expect(opened(OpenReport()) == .unlocked(notices: []))
    }

    @Test func noticesFromTheOpenReport() {
        var report = OpenReport()
        report.newestChangeMayBeLost = true
        report.recoveredFromPages = true
        report.repairWaitingForSpace = true
        #expect(
            opened(report) == .unlocked(notices: [.newestChangeMayBeLost, .recoveredFromPages, .repairWaitingForSpace]))
    }

    // MARK: Cancels keep the lock cover and never count as a failure

    @Test(arguments: [0, 1, 5])
    func cancels(failuresInARow: Int) {
        #expect(outcome(VaultError.vaultKeyUnavailable(status: -128), failuresInARow: failuresInARow) == .lockCover)
        #expect(outcome(VaultError.locked, failuresInARow: failuresInARow) == .lockCover)
        // The app left the foreground while the prompt was up: the system cancels it with -25293.
        #expect(
            outcome(
                VaultError.vaultKeyUnavailable(status: -25293), failuresInARow: failuresInARow, leftForeground: true)
                == .lockCover)
    }

    // MARK: Key states

    @Test func passcodeTurnedOff() {
        #expect(
            outcome(VaultError.vaultKeyUnavailable(status: -25293), passcode: .notSet) == .recovery(.passcodeTurnedOff))
    }

    @Test func phoneLockedDuringOpen() {
        #expect(outcome(VaultError.vaultKeyUnavailable(status: -25308)) == .recovery(.unlockPhoneAndRetry))
        #expect(outcome(VaultError.fileUnavailable) == .recovery(.unlockPhoneAndRetry))
    }

    @Test(arguments: [
        VaultError.vaultKeyUnavailable(status: -25293), .vaultKeyUnavailable(status: nil),
        .vaultKeyUnavailable(status: -34018),
    ])
    func anyOtherStatusPromptsAgainThenStopsAfterTwoFailures(_ error: VaultError) {
        #expect(outcome(error, failuresInARow: 0) == .promptAgain)
        #expect(outcome(error, failuresInARow: 1) == .recovery(.cannotOpenNow))
        #expect(outcome(error, failuresInARow: 4) == .recovery(.cannotOpenNow))
    }

    @Test func keyMissing() {
        #expect(outcome(VaultError.vaultKeyMissing) == .recovery(.keyMissing))
    }

    // MARK: Files

    @Test func vaultThatCannotBeOpened() {
        #expect(outcome(VaultError.vaultUnreadable) == .recovery(.vaultUnreadable))
        #expect(outcome(VaultError.vaultHeaderMissing) == .recovery(.vaultUnreadable))
        #expect(outcome(VaultError.corruptFile) == .recovery(.vaultUnreadable))
    }

    @Test func newerVersion() {
        #expect(outcome(VaultError.unsupportedVersion) == .recovery(.updateApp))
    }

    @Test func storageFullFromOpen() {
        #expect(outcome(VaultError.storageFull) == .recovery(.storageFullOnOpen))
    }

    @Test func anyOtherErrorFromOpen() {
        #expect(outcome(CocoaError(.fileReadUnknown)) == .recovery(.cannotOpenNow))
        #expect(outcome(VaultError.authenticationFailed) == .recovery(.cannotOpenNow))
    }

    // MARK: Saves

    @Test func saveFailures() {
        #expect(RecoveryMapping.screen(forSaveError: VaultError.storageFull) == .storageFullOnSave)
        // The lock cover already explains a save cut short by locking.
        #expect(RecoveryMapping.screen(forSaveError: VaultError.locked) == nil)
        #expect(RecoveryMapping.screen(forSaveError: VaultError.documentDeleted) == .saveFailed)
        #expect(RecoveryMapping.screen(forSaveError: CocoaError(.fileWriteUnknown)) == .saveFailed)
    }

    /// What reaches the log: the error's kind, never a path, id or value.
    @Test func errorSummaryLeavesOutPathsAndValues() {
        let withPath = CocoaError(.fileReadNoSuchFile, userInfo: [NSFilePathErrorKey: "/Vault/pages/abc.enc"])
        let summary = ErrorSummary.describe(withPath)
        #expect(summary == "NSCocoaErrorDomain 260")
        #expect(!summary.contains("/") && !summary.contains("abc"))
        #expect(ErrorSummary.describe(VaultError.vaultKeyUnavailable(status: -128)).contains("-128"))
    }
}
