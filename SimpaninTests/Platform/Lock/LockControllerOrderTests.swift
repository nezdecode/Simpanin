//
//  LockControllerOrderTests.swift
//  SimpaninTests
//
//  Created by Inez Amanda on 18/11/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Crypto
import Foundation
import Testing

@testable import Simpanin
@testable import VaultCore

/// One lock or unlock at a time: a lock never waits for an open, an open waits for every lock already decided and
/// for the open before it, and a return waits for both.
@MainActor
@Suite("Lock controller, one lock or unlock at a time", .timeLimit(.minutes(1)))
struct LockControllerOrderTests {
    let clock = ManualClock()

    func unlocked(_ vault: FakeVault, autoLock: AutoLock = .oneMinute) async -> LockController {
        let clock = clock
        let controller = LockController.make(vault, now: { clock.now }, autoLock: autoLock)
        await controller.sceneDidBecomeActive()
        return controller
    }

    /// Long enough for an open that doesn't wait to reach the fake store, which answers at once.
    func letTheMainActorRun() async {
        try? await Task.sleep(for: .milliseconds(100))
    }

    /// Buka while a second lock is still on its way: the store could answer an open that ran first from the vault
    /// it is about to lock, with no prompt.
    @Test func anUnlockWaitsForALockStillLanding() async {
        let vault = FakeVault([])
        let controller = await unlocked(vault)
        await controller.lock()
        #expect(controller.state == .locked)
        await vault.gateNextLock()
        let locking = Task { await controller.protectedDataWillBecomeUnavailable() }
        #expect(await vault.waitUntilLocking())
        let opening = Task { await controller.unlock() }
        await letTheMainActorRun()
        #expect(await vault.openCount == 1)
        await vault.releaseLock()
        await locking.value
        await opening.value
        #expect(controller.state == .unlocked)
        #expect(await vault.openCount == 2)
    }

    /// A Kunci or a phone lock still waiting for a busy store when the app leaves: the return waits for it, then
    /// prompts once, as it does when the lock has already landed.
    @Test(arguments: [false, true], [AutoLock.oneMinute, .immediately])
    func aReturnWaitsForALockStillLandingAndPromptsOnce(phoneLock: Bool, autoLock: AutoLock) async {
        let vault = FakeVault([])
        let controller = await unlocked(vault, autoLock: autoLock)
        await vault.gateNextLock()
        let locking = Task {
            if phoneLock {
                await controller.protectedDataWillBecomeUnavailable()
            } else {
                await controller.lock()
            }
        }
        #expect(await vault.waitUntilLocking())
        controller.sceneDidBecomeInactive()
        controller.sceneDidEnterBackground()
        let returning = Task { await controller.sceneDidBecomeActive() }
        await letTheMainActorRun()
        #expect(await vault.openCount == 1)
        await vault.releaseLock()
        await locking.value
        await returning.value
        #expect(controller.state == .unlocked)
        #expect(await vault.openCount == 2)
    }

    /// A Face ID read the leave cancelled, as a system cancel returns it.
    static let leftDuringThePrompt = Result<OpenReport, VaultError>.failure(.vaultKeyUnavailable(status: -25293))

    /// With Langsung, two round trips while a save holds the first leave lock: the second leave lock lands before
    /// the prompt, so no Buka shows over it, and the two returns share one prompt.
    @Test func twoQuickReturnsWithImmediatelyPromptOnce() async {
        let vault = FakeVault([])
        let controller = await unlocked(vault, autoLock: .immediately)
        await vault.gateNextLock()
        controller.sceneDidBecomeInactive()
        controller.sceneDidEnterBackground()
        #expect(await vault.waitUntilLocking())
        let first = Task { await controller.sceneDidBecomeActive() }
        // The first return starts its wait before the second leave, so both are returns, not one and a blip.
        await letTheMainActorRun()
        controller.sceneDidBecomeInactive()
        controller.sceneDidEnterBackground()
        let second = Task { await controller.sceneDidBecomeActive() }
        await letTheMainActorRun()
        await vault.gateNextOpen()
        await vault.releaseLock()
        #expect(await vault.waitUntilOpening())
        #expect(controller.state == .unlocking)
        await vault.release()
        await first.value
        await second.value
        #expect(controller.state == .unlocked)
        #expect(await vault.openCount == 2)
    }

    /// The store shares a pending open between callers and fails it once a lock reached the store. A return that
    /// joined the open the leave cancelled would get that failure and show Buka; it waits for it and prompts anew.
    @Test func aQuickReturnAfterLeavingDuringThePromptPromptsAgain() async throws {
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let keys = GatedKeyStore()
        let store = VaultStore(
            rootDirectory: folder.appending(path: "Vault"), projectionURL: folder.appending(path: "projection.json"),
            keyStore: keys, fileProtector: DataProtectionFileProtector())
        let clock = clock
        let controller = LockController.make(store, now: { clock.now }, autoLock: .immediately)
        await controller.sceneDidBecomeActive()
        #expect(controller.state == .unlocked)
        await controller.lock()
        // Creating the vault looked the key up once already.
        let readsBefore = await keys.reads
        await keys.gateNextRead()
        let opening = Task { await controller.unlock() }
        #expect(await keys.waitUntilReading())
        controller.sceneDidBecomeInactive()
        controller.sceneDidEnterBackground()
        let returning = Task { await controller.sceneDidBecomeActive() }
        await letTheMainActorRun()
        await keys.gateNextRead()
        await keys.release()
        #expect(await keys.waitUntilReading())
        await keys.release()
        await opening.value
        await returning.value
        #expect(controller.state == .unlocked)
        // The read the leave cancelled, and the return's own.
        #expect(await keys.reads == readsBefore + 2)
    }

    /// Buka's open runs while the return still waits: one prompt, and the return, whose relock was decided before
    /// it waited, doesn't lock the vault Buka just opened. Swift doesn't promise which of two tasks waiting for the
    /// lost open resumes first, so both orders run, and in one of them Buka's open comes while the return waits.
    @Test(arguments: [true, false])
    func bukaWhileTheReturnWaitsForALostOpenPromptsOnce(bukaFirst: Bool) async {
        let vault = FakeVault([])
        let controller = await unlocked(vault, autoLock: .immediately)
        await controller.lock()
        await vault.gateNextOpen()
        let opening = Task { await controller.unlock() }
        #expect(await vault.waitUntilOpening())
        controller.sceneDidBecomeInactive()
        await controller.sceneDidEnterBackground()?.value
        var returning: Task<Void, Never>?
        if !bukaFirst { returning = Task { await controller.sceneDidBecomeActive() } }
        await letTheMainActorRun()
        let buka = Task { await controller.unlock() }
        await letTheMainActorRun()
        if bukaFirst { returning = Task { await controller.sceneDidBecomeActive() } }
        await letTheMainActorRun()
        await vault.release()
        await opening.value
        await returning?.value
        await buka.value
        #expect(controller.state == .unlocked)
        #expect(await vault.openCount == 3)
        // Kunci, the leave lock, and the lost open locking the store again.
        #expect(await vault.lockCount == 3)
    }

    /// 1 menit, back before the read the leave cancelled has come back: the return waits for it, then prompts.
    @Test func aReturnBeforeACancelledPromptEndsPromptsOnce() async {
        let vault = FakeVault([Self.leftDuringThePrompt, .success(OpenReport())], gated: true, onlyFirstGated: true)
        let clock = clock
        let controller = LockController.make(vault, now: { clock.now })
        let launching = Task { await controller.sceneDidBecomeActive() }
        #expect(await vault.waitUntilOpening())
        controller.sceneDidBecomeInactive()
        controller.sceneDidEnterBackground()
        let returning = Task { await controller.sceneDidBecomeActive() }
        await letTheMainActorRun()
        await vault.release()
        await launching.value
        await returning.value
        #expect(controller.state == .unlocked)
        #expect(await vault.openCount == 2)
    }

    @Test func tappingBukaDuringAnOpenOpensOnce() async {
        let vault = FakeVault([], gated: true)
        let clock = clock
        let controller = LockController.make(vault, now: { clock.now })
        let launching = Task { await controller.sceneDidBecomeActive() }
        #expect(await vault.waitUntilOpening())
        let buka = Task { await controller.unlock() }
        await letTheMainActorRun()
        await vault.release()
        await launching.value
        await buka.value
        #expect(controller.state == .unlocked)
        #expect(await vault.openCount == 1)
    }

    /// The phone locks while a return waits for a lost open. If its notice comes first, the return waits for
    /// protected data; if the app leaves first, as on a device, the next return prompts.
    @Test(arguments: [true, false])
    func aPhoneLockDuringTheReturnsWait(noticeFirst: Bool) async {
        let vault = FakeVault([])
        let conditions = LaunchConditions()
        conditions.empty = false
        conditions.headerExists = true
        let controller = conditions.makeController(vault, clock: clock, autoLock: .immediately)
        await controller.sceneDidBecomeActive()
        await controller.lock()
        await vault.gateNextOpen()
        let opening = Task { await controller.unlock() }
        #expect(await vault.waitUntilOpening())
        controller.sceneDidBecomeInactive()
        await controller.sceneDidEnterBackground()?.value
        let returning = Task { await controller.sceneDidBecomeActive() }
        await letTheMainActorRun()
        conditions.protectedData = false
        if noticeFirst {
            await controller.protectedDataWillBecomeUnavailable()
        } else {
            controller.sceneDidBecomeInactive()
            controller.sceneDidEnterBackground()
            await controller.protectedDataWillBecomeUnavailable()
        }
        await vault.release()
        await opening.value
        await returning.value
        #expect(controller.state == .locked)
        #expect(await vault.openCount == 2)
        conditions.protectedData = true
        if noticeFirst {
            await controller.protectedDataDidBecomeAvailable()
        } else {
            await controller.sceneDidBecomeActive()
        }
        #expect(controller.state == .unlocked)
        #expect(await vault.openCount == 3)
    }

    /// 1 menit: Face ID passed and the index is still loading when the user goes Home; back after the timeout, that
    /// open loses to the return's lock, and the return asks again.
    @Test func anOpenStillRunningAtATimedOutReturnIsDroppedForAFreshPrompt() async {
        let vault = FakeVault([])
        let controller = await unlocked(vault)
        await controller.lock()
        await vault.gateNextOpen()
        let opening = Task { await controller.unlock() }
        #expect(await vault.waitUntilOpening())
        controller.sceneDidBecomeInactive()
        controller.sceneDidEnterBackground()
        clock.advance(by: .seconds(120))
        let returning = Task { await controller.sceneDidBecomeActive() }
        await letTheMainActorRun()
        await vault.release()
        await opening.value
        await returning.value
        #expect(controller.state == .unlocked)
        #expect(await vault.openCount == 3)
    }

    /// A read the leave cancelled is a cancel: no retry while away, and not one of the two failures in a row.
    @Test func aCancelByLeavingDuringThePromptIsNotCounted() async {
        let failed = Result<OpenReport, VaultError>.failure(.vaultKeyUnavailable(status: -99))
        let vault = FakeVault(
            [Self.leftDuringThePrompt, failed, .success(OpenReport())], gated: true, onlyFirstGated: true)
        let clock = clock
        let controller = LockController.make(vault, now: { clock.now })
        let launching = Task { await controller.sceneDidBecomeActive() }
        #expect(await vault.waitUntilOpening())
        controller.sceneDidBecomeInactive()
        controller.sceneDidEnterBackground()
        await vault.release()
        await launching.value
        #expect(controller.state == .locked)
        #expect(await vault.openCount == 1)
        await controller.sceneDidBecomeActive()
        #expect(controller.state == .unlocked)
        #expect(await vault.openCount == 3)
    }
}

/// Keeps the vault key in memory, with a read that can wait like a Face ID prompt still on screen.
actor GatedKeyStore {
    private let keys = PreviewKeyStore()
    private(set) var reads = 0
    private var nextGated = false
    private var gate: CheckedContinuation<Void, Never>?

    func gateNextRead() { nextGated = true }

    func readVaultKey(for vaultID: VaultID) async throws -> SymmetricKey {
        reads += 1
        if nextGated {
            nextGated = false
            await withCheckedContinuation { gate = $0 }
        }
        return try await keys.readVaultKey(for: vaultID)
    }

    func createVaultKey(for vaultID: VaultID) async throws -> SymmetricKey {
        try await keys.createVaultKey(for: vaultID)
    }

    func deleteVaultKey(for vaultID: VaultID) async throws {
        try await keys.deleteVaultKey(for: vaultID)
    }

    /// False if no read started within two seconds, so a broken controller fails the test instead of hanging it.
    func waitUntilReading() async -> Bool {
        for _ in 0..<2_000 where gate == nil {
            try? await Task.sleep(for: .milliseconds(1))
        }
        return gate != nil
    }

    func release() {
        gate?.resume()
        gate = nil
    }
}

// In an extension, like FakeVault's: see Fakes.swift.
extension GatedKeyStore: KeyStore {}
