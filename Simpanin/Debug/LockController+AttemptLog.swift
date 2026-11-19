//
//  LockController+AttemptLog.swift
//  Simpanin
//
//  Created by Inez Amanda on 19/11/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

#if DEBUG
    import VaultCore

    extension LockController {
        /// Statuses only: VaultError cases carry no ids or values, other errors show their type.
        static func describe(_ result: Result<OpenReport, any Error>) -> String {
            switch result {
            case .success: "opened"
            case .failure(let error): ErrorSummary.describe(error)
            }
        }
    }
#endif
