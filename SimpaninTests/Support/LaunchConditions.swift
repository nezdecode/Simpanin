//
//  LaunchConditions.swift
//  SimpaninTests
//
//  Created by Inez Amanda on 4/11/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import Testing

@testable import Simpanin

/// What the phone looks like to the lock, changed by the test as it goes.
@MainActor
final class LaunchConditions {
    var passcode = PasscodeState.set
    var headerExists = false
    var empty = true
    var emptyCheckFails = false
    var protectedData = true
    private(set) var emptyChecks = 0

    func isEmpty() throws -> Bool {
        emptyChecks += 1
        if emptyCheckFails { throw CocoaError(.fileReadNoPermission) }
        return empty
    }

    /// After `open()` has created the vault.
    func vaultCreated() {
        headerExists = true
        empty = false
    }
}

extension LaunchConditions {
    func makeController(_ vault: FakeVault, clock: ManualClock) -> LockController {
        LockController(
            vault: vault, now: { clock.now }, autoLock: .oneMinute, passcode: { self.passcode },
            vaultExists: { self.headerExists }, vaultIsEmpty: { try self.isEmpty() },
            protectedDataAvailable: { self.protectedData })
    }

    /// The welcome is up, nothing opened yet.
    func welcome(_ vault: FakeVault, clock: ManualClock) async -> LockController {
        let controller = makeController(vault, clock: clock)
        await controller.sceneDidBecomeActive()
        #expect(controller.state == .noVault)
        return controller
    }
}
