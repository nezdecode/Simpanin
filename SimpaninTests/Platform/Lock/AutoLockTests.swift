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
        let controller = LockController.make(FakeVault([]), settings: defaults)
        controller.setAutoLock(.fiveMinutes)
        #expect(controller.autoLock == .fiveMinutes)
        #expect(controller.relockTimeout == 300)
        #expect(AutoLock.stored(in: defaults) == .fiveMinutes)
        controller.setAutoLock(.immediately)
        #expect(controller.autoLock == .immediately)
        #expect(controller.relockTimeout == 0)
        #expect(AutoLock.stored(in: defaults) == .immediately)
    }

    // MARK: The time away

    let clock = ManualClock()

    /// Open, with `choice` as the Kunci otomatis time.
    func unlocked(_ vault: FakeVault, autoLock choice: AutoLock = .oneMinute) async -> LockController {
        let clock = clock
        let controller = LockController.make(vault, now: { clock.now }, autoLock: choice, settings: defaults())
        await controller.sceneDidBecomeActive()
        return controller
    }

    @Test func immediatelyRelocksOnAnyReturn() async {
        let vault = FakeVault([])
        let controller = await unlocked(vault)
        controller.setAutoLock(.immediately)
        controller.sceneDidEnterBackground()
        clock.advance(by: .seconds(1))
        await controller.sceneDidBecomeActive()
        #expect(await vault.lockCount == 1)
        #expect(await vault.openCount == 2)
    }

    /// "Langsung" drops the keys as the app leaves, so none wait in a suspended app for the next open.
    @Test func immediatelyLocksAsTheAppLeaves() async {
        let vault = FakeVault([])
        let controller = await unlocked(vault, autoLock: .immediately)
        await controller.sceneDidEnterBackground()?.value
        #expect(controller.state == .locked)
        #expect(await vault.lockCount == 1)
    }

    @Test(arguments: [AutoLock.oneMinute, .fiveMinutes])
    func theOtherChoicesKeepTheKeysWhenTheAppLeaves(_ choice: AutoLock) async {
        let vault = FakeVault([])
        let controller = await unlocked(vault, autoLock: choice)
        #expect(controller.sceneDidEnterBackground() == nil)
        #expect(controller.state == .unlocked)
        #expect(await vault.lockCount == 0)
    }

    /// Leaving cancels the prompt; an open that had already passed Face ID is dropped too.
    @Test func immediatelyLocksWhenLeavingDuringThePrompt() async {
        let vault = FakeVault([], gated: true, onlyFirstGated: true)
        let clock = clock
        let controller = LockController.make(
            vault, now: { clock.now }, autoLock: .immediately, settings: defaults())
        let opening = Task { await controller.sceneDidBecomeActive() }
        #expect(await vault.waitUntilOpening())
        controller.sceneDidBecomeInactive()
        let leaving = controller.sceneDidEnterBackground()
        await vault.release()
        await opening.value
        await leaving?.value
        #expect(controller.state == .locked)
        await controller.sceneDidBecomeActive()
        #expect(controller.state == .unlocked)
        #expect(await vault.openCount == 2)
    }

    /// No keys are held on these screens, and a lock would turn a recovery screen into the lock cover.
    @Test(arguments: [
        Result<OpenReport, VaultError>.failure(.vaultKeyUnavailable(status: -128)), .failure(.vaultKeyMissing), nil,
    ])
    func immediatelyLocksNothingOnTheCoverWelcomeOrARecoveryScreen(_ open: Result<OpenReport, VaultError>?) async {
        let vault = FakeVault(open.map { [$0] } ?? [])
        let clock = clock
        let controller = LockController.make(
            vault, now: { clock.now }, autoLock: .immediately, settings: defaults(), vaultIsEmpty: { open == nil })
        await controller.sceneDidBecomeActive()
        let screen = controller.state
        #expect(screen != .unlocked)
        #expect(controller.sceneDidEnterBackground() == nil)
        #expect(controller.state == screen)
        #expect(await vault.lockCount == 0)
    }

    @Test func aScanInProgressWhenTheAppLeavesIsToldAfterUnlocking() async throws {
        let controller = await unlocked(FakeVault([]), autoLock: .immediately)
        controller.scanStarted(.camera)
        let leaving = try #require(controller.sceneDidEnterBackground())
        await leaving.value
        #expect(controller.state == .locked)
        await controller.sceneDidBecomeActive()
        #expect(controller.notices.contains(.scanDropped))
    }

    /// The real clock can't run backwards. If the time away ever comes out negative, the vault locks rather
    /// than stays open, as it did when the phone's date was set back.
    @Test(arguments: AutoLock.allCases)
    func aClockThatRanBackwardsRelocks(_ choice: AutoLock) async {
        let vault = FakeVault([])
        let controller = await unlocked(vault, autoLock: choice)
        controller.sceneDidEnterBackground()
        clock.advance(by: .seconds(-3600))
        await controller.sceneDidBecomeActive()
        #expect(await vault.lockCount == 1)
        #expect(await vault.openCount == 2)
    }

    nonisolated static let trips: [(AutoLock, Duration, Bool)] = [
        (.immediately, .zero, true),
        (.oneMinute, .seconds(60) - .milliseconds(1), false),
        (.oneMinute, .seconds(60), true),
        (.fiveMinutes, .seconds(300) - .milliseconds(1), false),
        (.fiveMinutes, .seconds(300), true),
    ]

    @Test(arguments: trips)
    func returningRelocksOnlyFromTheChosenTime(_ choice: AutoLock, away: Duration, relocks: Bool) async {
        let vault = FakeVault([])
        let controller = await unlocked(vault, autoLock: choice)
        controller.sceneDidEnterBackground()
        clock.advance(by: away)
        await controller.sceneDidBecomeActive()
        #expect(await vault.lockCount == (relocks ? 1 : 0))
        #expect(await vault.openCount == (relocks ? 2 : 1))
    }

    @Test func eachTimeAwayIsCountedFromItsOwnStart() async {
        let vault = FakeVault([])
        let controller = await unlocked(vault)
        for _ in 1...2 {
            controller.sceneDidEnterBackground()
            clock.advance(by: .seconds(40))
            await controller.sceneDidBecomeActive()
        }
        #expect(controller.state == .unlocked)
        #expect(await vault.lockCount == 0)
    }

    /// Control Centre, a call or the app switcher cover the content but start no timer, also right after a
    /// return from the background.
    @Test func timePassedWhileOnlyInactiveNeverRelocks() async {
        let vault = FakeVault([])
        let controller = await unlocked(vault)
        controller.sceneDidEnterBackground()
        clock.advance(by: .seconds(40))
        await controller.sceneDidBecomeActive()
        controller.sceneDidBecomeInactive()
        clock.advance(by: .seconds(600))
        await controller.sceneDidBecomeActive()
        #expect(controller.state == .unlocked)
        #expect(await vault.lockCount == 0)
    }
}
