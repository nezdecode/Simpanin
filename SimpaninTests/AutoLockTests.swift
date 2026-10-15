//
//  AutoLockTests.swift
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

@MainActor
@Suite("Auto-lock setting")
struct AutoLockTests {
    func defaults() -> UserDefaults {
        let name = "AutoLockTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func choicesAndDefault() {
        #expect(AutoLock.allCases.map(\.seconds) == [0, 60, 300])
        #expect(AutoLock.stored(in: defaults()) == .oneMinute)
        #expect(String(localized: AutoLock.immediately.title) == "Langsung")
        #expect(String(localized: AutoLock.oneMinute.title) == "Setelah 1 menit")
        #expect(String(localized: AutoLock.fiveMinutes.title) == "Setelah 5 menit")
    }

    /// The stored values are what's already on people's phones: renaming a case must not change them.
    @Test func storedValuesNeverChange() {
        let stored: [String: AutoLock] = [
            "immediately": .immediately, "oneMinute": .oneMinute, "fiveMinutes": .fiveMinutes,
        ]
        for (value, choice) in stored {
            #expect(AutoLock(rawValue: value) == choice)
        }
        let defaults = defaults()
        AutoLock.fiveMinutes.store(in: defaults)
        #expect(defaults.string(forKey: "autoLock") == "fiveMinutes")
    }

    @Test func choiceIsKept() {
        let defaults = defaults()
        AutoLock.fiveMinutes.store(in: defaults)
        #expect(AutoLock.stored(in: defaults) == .fiveMinutes)
    }

    @Test func launchUsesTheStoredChoice() {
        let defaults = defaults()
        AutoLock.fiveMinutes.store(in: defaults)
        let fiveMinutes = RootView.makeLock(for: .preview(), defaults: defaults)
        #expect(fiveMinutes.autoLock == .fiveMinutes)
        #expect(fiveMinutes.relockTimeout == 300)
        AutoLock.immediately.store(in: defaults)
        let immediately = RootView.makeLock(for: .preview(), defaults: defaults)
        #expect(immediately.autoLock == .immediately)
        #expect(immediately.relockTimeout == 0)
    }

    @Test func settingTheChoiceSavesAndAppliesIt() {
        let defaults = defaults()
        let controller = LockController(
            vault: FakeVault([]), clock: FixedClock(), settings: defaults, passcode: { .set }, vaultExists: { true },
            protectedDataAvailable: { true })
        controller.setAutoLock(.fiveMinutes)
        #expect(controller.autoLock == .fiveMinutes)
        #expect(controller.relockTimeout == 300)
        #expect(AutoLock.stored(in: defaults) == .fiveMinutes)
        controller.setAutoLock(.immediately)
        #expect(controller.autoLock == .immediately)
        #expect(controller.relockTimeout == 0)
        #expect(AutoLock.stored(in: defaults) == .immediately)
    }

    @Test func immediatelyRelocksOnAnyReturn() async {
        let clock = FixedClock()
        let vault = FakeVault([])
        let controller = LockController(
            vault: vault, clock: clock, settings: defaults(), passcode: { .set }, vaultExists: { true },
            protectedDataAvailable: { true })
        await controller.sceneDidBecomeActive()
        controller.setAutoLock(.immediately)
        controller.sceneDidEnterBackground()
        clock.advance(by: 1)
        await controller.sceneDidBecomeActive()
        #expect(await vault.lockCount == 1)
        #expect(await vault.openCount == 2)
    }
}
