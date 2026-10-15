//
//  UnlockMethodTests.swift
//  SimpaninTests
//
//  Created by Inez Amanda on 14/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import LocalAuthentication
import Testing

@testable import Simpanin

@Suite("Unlock method")
struct UnlockMethodTests {
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
}
