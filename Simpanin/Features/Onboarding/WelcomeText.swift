//
//  WelcomeText.swift
//  Simpanin
//
//  Created by Inez Amanda on 3/11/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

/// The welcome screen's words that depend on the phone.
nonisolated enum WelcomeText {
    /// How the vault is locked. Face ID turned off for Simpanin, and Optic ID, which no iPhone has,
    /// read as the passcode.
    static func lockLine(for method: UnlockMethod) -> LocalizedStringResource {
        switch method {
        case .faceID: "welcome.lock.faceID"
        case .touchID: "welcome.lock.touchID"
        case .passcode, .faceIDTurnedOff, .opticID: "welcome.lock.passcode"
        }
    }
}
