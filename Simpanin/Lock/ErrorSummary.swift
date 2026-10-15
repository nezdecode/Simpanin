//
//  ErrorSummary.swift
//  Simpanin
//
//  Created by Inez Amanda on 14/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import VaultCore

/// An error as it may be logged: the VaultError case, which carries only a Keychain status,
/// or the domain and code of any other error. Its message and details can hold file paths.
nonisolated enum ErrorSummary {
    static func describe(_ error: any Error) -> String {
        if let error = error as? VaultError { return String(describing: error) }
        let error = error as NSError
        return "\(error.domain) \(error.code)"
    }
}
