//
//  LockControllerTests.swift
//  SimpaninTests
//
//  Created by Inez Amanda on 14/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import Synchronization
import Testing

@testable import Simpanin
@testable import VaultCore

/// Answers open() from a list of results. A gated open waits until the test releases it, like
/// a prompt that is still on screen.
actor FakeVault: VaultOpening {
    private var results: [Result<OpenReport, VaultError>]
    private(set) var openCount = 0
    private(set) var lockCount = 0
    private var gate: CheckedContinuation<Void, Never>?
    private let gated: Bool
    private let onlyFirstGated: Bool

    /// - Parameter onlyFirstGated: later opens answer at once, so a retry the test doesn't
    ///   expect fails the test instead of hanging it.
    init(_ results: [Result<OpenReport, VaultError>], gated: Bool = false, onlyFirstGated: Bool = false) {
        self.results = results
        self.gated = gated
        self.onlyFirstGated = onlyFirstGated
    }

    func open() async throws -> OpenReport {
        openCount += 1
        if gated, !onlyFirstGated || openCount == 1 { await withCheckedContinuation { gate = $0 } }
        let result = results.isEmpty ? .success(OpenReport()) : results.removeFirst()
        return try result.get()
    }

    func lock() async { lockCount += 1 }

    /// False if open() didn't start within two seconds, so a broken controller fails the test
    /// instead of hanging it.
    func waitUntilOpening() async -> Bool {
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

final class FixedClock: VaultClock {
    private let date = Mutex(Date(timeIntervalSince1970: 1_790_000_000))
    var now: Date { date.withLock { $0 } }
    func advance(by seconds: TimeInterval) { date.withLock { $0 += seconds } }
}

@MainActor
@Suite("Lock controller")
struct LockControllerTests {
    let clock = FixedClock()

    func makeController(
        _ vault: FakeVault, passcode: PasscodeState = .set, vaultExists: Bool = true,
        protectedData: @escaping @MainActor () -> Bool = { true }
    ) -> LockController {
        LockController(
            vault: vault, clock: clock, relockTimeout: 60, passcode: { passcode }, vaultExists: { vaultExists },
            protectedDataAvailable: protectedData)
    }

    static func unavailable(_ status: Int32?) -> Result<OpenReport, VaultError> {
        .failure(.vaultKeyUnavailable(status: status))
    }

    // MARK: Lifecycle table

    @Test func launchPromptsOnce() async {
        let vault = FakeVault([])
        let controller = makeController(vault)
        await controller.sceneDidBecomeActive()
        #expect(controller.state == .unlocked)
        #expect(await vault.openCount == 1)
    }

    @Test func inactiveCoversContentButKeepsKeys() async {
        let vault = FakeVault([])
        let controller = makeController(vault)
        await controller.sceneDidBecomeActive()
        controller.sceneDidBecomeInactive()
        #expect(controller.coverShown && controller.contentHidden)
        await controller.sceneDidBecomeActive()
        #expect(!controller.coverShown && !controller.contentHidden)
        #expect(controller.state == .unlocked)
        #expect(await vault.openCount == 1)
        #expect(await vault.lockCount == 0)
    }

    @Test func returningBeforeTheTimeoutStaysUnlocked() async {
        let vault = FakeVault([])
        let controller = makeController(vault)
        await controller.sceneDidBecomeActive()
        controller.sceneDidEnterBackground()
        clock.advance(by: 59)
        await controller.sceneDidBecomeActive()
        #expect(controller.state == .unlocked)
        #expect(await vault.lockCount == 0)
        #expect(await vault.openCount == 1)
    }

    @Test func returningAfterTheTimeoutRelocksAndPrompts() async {
        let vault = FakeVault([])
        let controller = makeController(vault)
        await controller.sceneDidBecomeActive()
        controller.sceneDidEnterBackground()
        clock.advance(by: 60)
        await controller.sceneDidBecomeActive()
        #expect(await vault.lockCount == 1)
        #expect(await vault.openCount == 2)
        #expect(controller.state == .unlocked)
    }

    @Test func phoneLockingLocksAtOnce() async {
        let vault = FakeVault([])
        let controller = makeController(vault)
        await controller.sceneDidBecomeActive()
        await controller.protectedDataWillBecomeUnavailable()
        #expect(controller.state == .locked)
        #expect(await vault.lockCount == 1)
    }

    @Test func tappingLockLocksAtOnce() async {
        let vault = FakeVault([])
        let controller = makeController(vault)
        await controller.sceneDidBecomeActive()
        await controller.lock()
        #expect(controller.state == .locked)
        #expect(controller.contentHidden)
        #expect(await vault.lockCount == 1)
    }

    @Test func opensOnlyWhenProtectedDataIsAvailable() async {
        let vault = FakeVault([])
        let available = Mutex(false)
        let controller = makeController(vault, protectedData: { available.withLock { $0 } })
        await controller.sceneDidBecomeActive()
        #expect(await vault.openCount == 0)
        #expect(controller.state == .locked)
        available.withLock { $0 = true }
        await controller.protectedDataDidBecomeAvailable()
        #expect(await vault.openCount == 1)
        #expect(controller.state == .unlocked)
    }

    @Test func screenCaptureHidesContent() async {
        let controller = makeController(FakeVault([]))
        await controller.sceneDidBecomeActive()
        #expect(!controller.contentHidden)
        controller.screenCaptured = true
        #expect(controller.contentHidden)
    }

    // MARK: Recovery

    @Test func noPasscodeShowsAScreenWithoutAPrompt() async {
        let vault = FakeVault([])
        let controller = makeController(vault, passcode: .notSet, vaultExists: false)
        await controller.sceneDidBecomeActive()
        #expect(controller.state == .recovery(.passcodeNeeded))
        #expect(await vault.openCount == 0)
    }

    @Test func cancelKeepsTheCoverAndNeverPromptsByItself() async {
        let vault = FakeVault([Self.unavailable(-128)])
        let controller = makeController(vault)
        await controller.sceneDidBecomeActive()
        #expect(controller.state == .locked)
        // The prompt closing makes the app active again. That must not prompt again.
        controller.sceneDidBecomeInactive()
        await controller.sceneDidBecomeActive()
        #expect(await vault.openCount == 1)
        #expect(controller.state == .locked)
    }

    @Test func goingToTheHomeScreenDuringThePromptIsACancel() async {
        let vault = FakeVault([Self.unavailable(-25293), .success(OpenReport())], gated: true)
        let controller = makeController(vault)
        let opening = Task { await controller.sceneDidBecomeActive() }
        #expect(await vault.waitUntilOpening())
        #expect(controller.state == .unlocking)
        controller.sceneDidBecomeInactive()
        controller.sceneDidEnterBackground()
        await vault.release()
        await opening.value
        #expect(controller.state == .locked)
        #expect(await vault.openCount == 1)

        // Back from the home screen: one new prompt.
        let reopening = Task { await controller.sceneDidBecomeActive() }
        #expect(await vault.waitUntilOpening())
        await vault.release()
        await reopening.value
        #expect(controller.state == .unlocked)
        #expect(await vault.openCount == 2)
    }

    @Test func twoFailuresInARowShowTheScreenAndRetryStartsOver() async {
        let vault = FakeVault([Self.unavailable(nil), Self.unavailable(nil), Self.unavailable(nil)])
        let controller = makeController(vault)
        await controller.sceneDidBecomeActive()
        #expect(await vault.openCount == 2)  // prompted again once by itself
        #expect(controller.state == .recovery(.cannotOpenNow))

        // "Coba lagi" starts a fresh count: one failure prompts again, then it opens.
        await controller.unlock()
        #expect(await vault.openCount == 4)
        #expect(controller.state == .unlocked)
    }

    @Test func returningFromSettingsRetriesThePasscodeScreen() async {
        // "Settings link; retry on return": the user sets a passcode and comes back.
        let vault = FakeVault([])
        let passcode = Mutex(PasscodeState.notSet)
        let controller = LockController(
            vault: vault, clock: clock, passcode: { passcode.withLock { $0 } }, vaultExists: { false },
            protectedDataAvailable: { true })
        await controller.sceneDidBecomeActive()
        #expect(controller.state == .recovery(.passcodeNeeded))
        controller.sceneDidEnterBackground()
        passcode.withLock { $0 = .set }
        await controller.sceneDidBecomeActive()
        #expect(controller.state == .unlocked)
        #expect(await vault.openCount == 1)
    }

    @Test func returningDoesNotRetryAScreenThatNeedsADecision() async {
        let vault = FakeVault([.failure(.vaultKeyMissing)])
        let controller = makeController(vault)
        await controller.sceneDidBecomeActive()
        controller.sceneDidEnterBackground()
        await controller.sceneDidBecomeActive()
        #expect(controller.state == .recovery(.keyMissing))
        #expect(await vault.openCount == 1)
    }

    @Test func debugLogRecordsEachAttemptWithoutIdsOrValues() async throws {
        let vault = FakeVault([Self.unavailable(-128), .success(OpenReport())])
        let controller = makeController(vault)
        await controller.sceneDidBecomeActive()
        await controller.unlock()
        await controller.protectedDataWillBecomeUnavailable()
        let log = controller.attemptLog
        try #require(log.count == 3)
        #expect(log[0].contains("-128") && log[0].contains("lockCover"))
        #expect(log[1].contains("opened") && log[1].contains("unlocked"))
        #expect(log[2].contains("phone locked"))
    }

    @Test func phoneLockingDuringThePromptIsACancelWithoutARetry() async {
        // Check 7 on the iPhone: the phone locks while the prompt is up, and the interrupted
        // read returns -25293 before the app has left the foreground.
        let vault = FakeVault(
            [Self.unavailable(-25293), Self.unavailable(-25308)], gated: true, onlyFirstGated: true)
        let controller = makeController(vault)
        let opening = Task { await controller.sceneDidBecomeActive() }
        #expect(await vault.waitUntilOpening())
        await controller.protectedDataWillBecomeUnavailable()
        await vault.release()
        await opening.value
        #expect(controller.state == .locked)
        #expect(await vault.openCount == 1)  // no second prompt against a locked phone
    }

    @Test func aLockDuringASuccessfulOpenWins() async {
        // Face ID succeeds just as the phone locks: the open finishes after the lock.
        let vault = FakeVault([.success(OpenReport())], gated: true, onlyFirstGated: true)
        let controller = makeController(vault)
        let opening = Task { await controller.sceneDidBecomeActive() }
        #expect(await vault.waitUntilOpening())
        await controller.lock()
        await vault.release()
        await opening.value
        #expect(controller.state == .locked)
        #expect(controller.contentHidden)
        #expect(await vault.lockCount == 2)  // locked again, after the open finished
    }

    @Test func noticesFromOpening() async {
        var report = OpenReport()
        report.repairWaitingForSpace = true
        let controller = makeController(FakeVault([.success(report)]))
        await controller.sceneDidBecomeActive()
        #expect(controller.state == .unlocked)
        #expect(controller.notices == [.repairWaitingForSpace])
    }
}
