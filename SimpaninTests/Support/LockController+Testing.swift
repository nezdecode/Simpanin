//
//  LockController+Testing.swift
//  SimpaninTests
//
//  Created by Inez Amanda on 17/11/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

@testable import Simpanin

extension LockController {
    /// A phone with a passcode and protected data, and a saved vault that isn't empty, unless the test says otherwise.
    /// `settings` is the real `UserDefaults.standard`, so a test that calls `setAutoLock` passes a suite of its own.
    static func make(
        _ vault: any VaultOpening, now: @escaping @MainActor () -> ContinuousClock.Instant = { ContinuousClock.now },
        autoLock: AutoLock = .oneMinute, settings: UserDefaults = .standard,
        passcode: @escaping @MainActor () -> PasscodeState = { .set },
        vaultExists: @escaping @MainActor () -> Bool = { true },
        vaultIsEmpty: @escaping @MainActor () throws -> Bool = { false },
        protectedDataAvailable: @escaping @MainActor () -> Bool = { true }
    ) -> LockController {
        LockController(
            vault: vault, now: now, autoLock: autoLock, settings: settings, passcode: passcode,
            vaultExists: vaultExists, vaultIsEmpty: vaultIsEmpty, protectedDataAvailable: protectedDataAvailable)
    }
}
