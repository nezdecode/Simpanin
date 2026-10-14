//
//  LockController.swift
//  Simpanin
//
//  Created by Inez Amanda on 14/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import Observation
import VaultCore

/// What the lock needs from the vault, so tests can stand in for the real store.
nonisolated protocol VaultOpening: Sendable {
    func open() async throws -> OpenReport
    func lock() async
}

extension VaultStore: VaultOpening {}

/// The lock, following the design doc's lifecycle table. The clock, the store and the system
/// checks are injected, so the state machine is tested without waiting or a device.
@MainActor @Observable
final class LockController {
    enum State: Equatable {
        case locked, unlocking, unlocked
        case recovery(RecoveryScreen)
    }

    private(set) var state = State.locked
    /// One-time notices and the full-disk banner from the last open.
    private(set) var notices: Set<VaultNotice> = []
    /// Covers the content while the app is inactive or in the background. Keys may stay.
    private(set) var coverShown = false
    /// Set by the view while the screen is recorded or mirrored.
    var screenCaptured = false
    var contentHidden: Bool { state != .unlocked || coverShown || screenCaptured }

    let relockTimeout: TimeInterval
    private let vault: any VaultOpening
    private let clock: any VaultClock
    private let passcode: @MainActor () -> PasscodeState
    private let vaultExists: @MainActor () -> Bool
    private let protectedDataAvailable: @MainActor () -> Bool

    private var hasBeenActive = false
    private var backgroundedAt: Date?
    private var waitingForProtectedData = false
    private var leftForegroundDuringPrompt = false
    private var failuresInARow = 0
    /// Bumped by every lock, so an attempt that was waiting for the vault can tell it lost.
    private var lockCount = 0

    #if DEBUG
        /// For the device checks: each open attempt and lock event, as statuses only.
        private(set) var attemptLog: [String] = []
    #endif

    init(
        vault: any VaultOpening, clock: any VaultClock = SystemClock(), relockTimeout: TimeInterval = 60,
        passcode: @escaping @MainActor () -> PasscodeState = { PasscodeState.current() },
        vaultExists: @escaping @MainActor () -> Bool,
        protectedDataAvailable: @escaping @MainActor () -> Bool
    ) {
        self.vault = vault
        self.clock = clock
        self.relockTimeout = relockTimeout
        self.passcode = passcode
        self.vaultExists = vaultExists
        self.protectedDataAvailable = protectedDataAvailable
    }

    // MARK: - Scene phase

    /// The passcode screens send the user to Settings, so coming back retries by itself.
    private var retriesOnReturn: Bool {
        guard case .recovery(let screen) = state else { return false }
        return RecoveryContent(screen).action == .openSettings
    }

    /// Prompts only at launch and on a return from the background. The prompt itself makes the
    /// app inactive and active again, so prompting on every activation would loop after a cancel.
    func sceneDidBecomeActive() async {
        coverShown = false
        let returning = !hasBeenActive || backgroundedAt != nil
        hasBeenActive = true
        if let backgroundedAt, state == .unlocked, clock.now.timeIntervalSince(backgroundedAt) >= relockTimeout {
            await lock()
        }
        backgroundedAt = nil
        if returning, state == .locked || retriesOnReturn { await unlock() }
    }

    func sceneDidBecomeInactive() {
        coverShown = true
    }

    /// Suspended apps run no timers, so the timeout is checked on return.
    func sceneDidEnterBackground() {
        coverShown = true
        backgroundedAt = clock.now
        if state == .unlocking { leftForegroundDuringPrompt = true }
    }

    func protectedDataWillBecomeUnavailable() async {
        #if DEBUG
            attemptLog.append("phone locked")
        #endif
        await lock()
    }

    func protectedDataDidBecomeAvailable() async {
        guard waitingForProtectedData else { return }
        waitingForProtectedData = false
        await unlock()
    }

    // MARK: - Unlock and lock

    /// From the lock cover's "Buka" button, a recovery screen's retry, or by itself.
    func unlock() async {
        guard state != .unlocking, state != .unlocked else { return }
        guard protectedDataAvailable() else {
            waitingForProtectedData = true
            return
        }
        if let screen = RecoveryMapping.beforeOpening(passcode: passcode(), vaultExists: vaultExists()) {
            state = .recovery(screen)
            return
        }
        state = .unlocking
        leftForegroundDuringPrompt = false
        let lockCountAtStart = lockCount
        let result: Result<OpenReport, any Error>
        do {
            result = .success(try await vault.open())
        } catch {
            result = .failure(error)
        }
        // A lock that came in meanwhile (the user, or the phone locking) wins over the result. The
        // phone may lock before the app leaves the foreground, and the open may even finish after
        // the lock reached the store, so lock the store again and keep the cover.
        guard lockCount == lockCountAtStart else {
            #if DEBUG
                attemptLog.append("open: \(Self.describe(result)) -> dropped, locked meanwhile")
            #endif
            await vault.lock()
            state = .locked
            return
        }
        let outcome = RecoveryMapping.outcome(
            of: result, passcode: passcode(), failuresInARow: failuresInARow,
            leftForegroundDuringPrompt: leftForegroundDuringPrompt)
        #if DEBUG
            attemptLog.append("open: \(Self.describe(result)) -> \(outcome)")
        #endif
        await apply(outcome)
    }

    /// Notices are shown once: dismissing one hides it until the next open reports it again.
    func dismiss(_ notice: VaultNotice) {
        notices.remove(notice)
    }

    func lock() async {
        lockCount += 1
        await vault.lock()
        state = .locked
        notices = []
        failuresInARow = 0
    }

    #if DEBUG
        /// Statuses only: VaultError cases carry no ids or values, other errors show their type.
        private static func describe(_ result: Result<OpenReport, any Error>) -> String {
            switch result {
            case .success: "opened"
            case .failure(let error): ErrorSummary.describe(error)
            }
        }
    #endif

    private func apply(_ outcome: LockOutcome) async {
        switch outcome {
        case .unlocked(let notices):
            failuresInARow = 0
            self.notices = notices
            state = .unlocked
        case .lockCover:
            state = .locked
        case .promptAgain:
            failuresInARow += 1
            state = .locked
            await unlock()
        case .recovery(let screen):
            // A retry from the screen starts a fresh count.
            failuresInARow = 0
            state = .recovery(screen)
        }
    }
}
