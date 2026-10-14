//
//  PasscodeState.swift
//  Simpanin
//
//  Created by Inez Amanda on 13/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import LocalAuthentication

/// Whether the device has a passcode. Without one, `.userPresence` can never be satisfied, so
/// the app refuses to create a vault. Checking shows no prompt.
nonisolated enum PasscodeState: Equatable, Sendable {
    case set
    case notSet
    /// The check failed for another reason, so the passcode may still be set.
    case unknown(code: Int)

    static func current() -> PasscodeState {
        var error: NSError?
        let canEvaluate = LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
        return from(canEvaluate: canEvaluate, error: error)
    }

    static func from(canEvaluate: Bool, error: (any Error)?) -> PasscodeState {
        if canEvaluate { return .set }
        guard let error = error as? LAError else { return .unknown(code: (error as NSError?)?.code ?? 0) }
        return error.code == .passcodeNotSet ? .notSet : .unknown(code: error.code.rawValue)
    }
}
