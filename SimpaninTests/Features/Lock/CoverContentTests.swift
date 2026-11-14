//
//  CoverContentTests.swift
//  SimpaninTests
//
//  Created by Inez Amanda on 3/11/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import Testing
import VaultCore

@testable import Simpanin

@MainActor
@Suite("Cover content")
struct CoverContentTests {
    private func content(
        _ state: LockController.State, creating: Bool = false, recording: Bool = false, hold: Bool = false
    ) -> CoverContent {
        CoverContent(state: state, isCreatingVault: creating, screenCaptured: recording, holdsLockScreen: hold)
    }

    private func makeController(_ vault: FakeVault) -> LockController {
        LockController(
            vault: vault, passcode: { .set }, vaultExists: { true }, vaultIsEmpty: { false },
            protectedDataAvailable: { true })
    }

    /// Opens the vault, finishing the open while the app is inactive, as a Face ID prompt does.
    private func openWhileInactive(_ lock: LockController, _ vault: FakeVault) async throws {
        let launch = Task { await lock.sceneDidBecomeActive() }
        try #require(await vault.waitUntilOpening())
        lock.sceneDidBecomeInactive()
        await vault.release()
        await launch.value
        try #require(lock.state == .unlocked)
    }

    // MARK: The decision

    @Test(arguments: [LockController.State.locked, .unlocking], [false, true])
    func aLockedOrUnlockingVaultShowsTheLockScreen(_ state: LockController.State, _ recording: Bool) {
        #expect(content(state, recording: recording) == .lockScreen)
    }

    @Test func anOpenVaultCoveredShowsOnlyTheName() {
        #expect(content(.unlocked) == .nameOnly)
    }

    @Test func anOpenVaultWhileRecordingSaysWhy() {
        #expect(content(.unlocked, recording: true) == .recording)
    }

    @Test(arguments: [false, true])
    func recoveryAndTheWelcomeIgnoreRecording(_ recording: Bool) {
        #expect(content(.recovery(.keyMissing), recording: recording) == .recovery(.keyMissing))
        #expect(content(.noVault, recording: recording) == .welcome)
        #expect(content(.unlocking, creating: true, recording: recording) == .welcome)
    }

    @Test func theRecordingTextIsInTheCatalog() {
        #expect(
            String(localized: "cover.recording")
                == "Disembunyikan selama layar direkam atau ditampilkan di layar lain.")
    }

    // MARK: Through the lock

    @Test func unlockingWhileInactiveKeepsTheLockScreenUntilActive() async throws {
        let vault = FakeVault([], gated: true)
        let lock = makeController(vault)
        try await openWhileInactive(lock, vault)
        #expect(lock.contentHidden)
        #expect(CoverContent(lock) == .lockScreen)
        await lock.sceneDidBecomeActive()
        #expect(!lock.holdsLockScreen)
        #expect(!lock.contentHidden)
    }

    /// While recording the cover is up with the app active. A hold set then would never be cleared, and the
    /// open vault would stay behind "Terkunci" with no Buka.
    @Test func openingWhileActiveAndRecordingSetsNoHold() async {
        let lock = makeController(FakeVault([]))
        lock.screenCaptured = true
        await lock.sceneDidBecomeActive()
        #expect(lock.state == .unlocked)
        #expect(!lock.holdsLockScreen)
        #expect(CoverContent(lock) == .recording)
    }

    @Test func theHoldWinsOverRecordingUntilActive() async throws {
        let vault = FakeVault([], gated: true)
        let lock = makeController(vault)
        lock.screenCaptured = true
        try await openWhileInactive(lock, vault)
        #expect(CoverContent(lock) == .lockScreen)
        await lock.sceneDidBecomeActive()
        #expect(CoverContent(lock) == .recording)
    }

    @Test func recordingWinsOverInactive() async {
        let lock = makeController(FakeVault([]))
        await lock.sceneDidBecomeActive()
        lock.screenCaptured = true
        lock.sceneDidBecomeInactive()
        #expect(CoverContent(lock) == .recording)
    }

    @Test func recordingEndingShowsTheContent() async {
        let lock = makeController(FakeVault([]))
        await lock.sceneDidBecomeActive()
        lock.screenCaptured = true
        #expect(lock.contentHidden)
        lock.screenCaptured = false
        #expect(!lock.contentHidden)
    }

    @Test func lockingWhileRecordingShowsTheLockScreen() async {
        let lock = makeController(FakeVault([]))
        await lock.sceneDidBecomeActive()
        lock.screenCaptured = true
        #expect(CoverContent(lock) == .recording)
        await lock.lock()
        #expect(lock.state == .locked)
        #expect(CoverContent(lock) == .lockScreen)
    }
}
