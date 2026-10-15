//
//  UnlockMethod.swift
//  Simpanin
//
//  Created by Inez Amanda on 14/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import LocalAuthentication

/// How the phone unlocks the vault key, so the lock cover shows the right icon and words.
nonisolated enum UnlockMethod: Equatable, Sendable {
    case faceID, touchID, opticID, passcode
    /// The phone has Face ID, but the user turned it off for Simpanin. The passcode still works,
    /// and Simpanin's own page in Settings has the switch.
    case faceIDTurnedOff

    static func current() -> UnlockMethod {
        let context = LAContext()
        var error: NSError?
        let canUse = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        return from(biometryType: context.biometryType, canUseBiometrics: canUse, errorCode: error?.code)
    }

    static func from(biometryType: LABiometryType, canUseBiometrics: Bool, errorCode: Int?) -> UnlockMethod {
        if canUseBiometrics {
            switch biometryType {
            case .faceID: return .faceID
            case .touchID: return .touchID
            case .opticID: return .opticID
            default: return .passcode
            }
        }
        if biometryType == .faceID, errorCode == LAError.Code.biometryNotAvailable.rawValue { return .faceIDTurnedOff }
        return .passcode
    }

    var caption: LocalizedStringResource {
        switch self {
        case .faceID: "unlock.faceID"
        case .touchID: "unlock.touchID"
        case .opticID: "unlock.opticID"
        case .passcode, .faceIDTurnedOff: "unlock.passcode"
        }
    }

    var systemImage: String {
        switch self {
        case .faceID: "faceid"
        case .touchID: "touchid"
        case .opticID: "opticid"
        case .passcode, .faceIDTurnedOff: "lock.fill"
        }
    }
}
