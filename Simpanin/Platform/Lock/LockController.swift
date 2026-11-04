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

/// The lock: when the vault opens, locks, and shows a recovery screen. The clock, the store and the system
/// checks are injected, so the state machine is tested without waiting or a device.
@MainActor @Observable
final class LockController {
    enum State: Equatable {
        case locked, unlocking, unlocked
        /// Nothing on the phone could be a document yet, so nothing was opened or created.
        case noVault
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

    /// The one place the Kunci otomatis choice lives while the app runs; Settings reads it here,
    /// so the screen can't show a different choice than the lock uses.
    private(set) var autoLock: AutoLock
    /// Where the choice is saved. UI tests pass their own store, so they never touch the app's.
    private let settings: UserDefaults
    var relockTimeout: TimeInterval { autoLock.seconds }
    /// The same check the lock uses, so "+" can ask for a passcode before the first scan.
    var passcodeState: PasscodeState { passcode() }
    private let vault: any VaultOpening
    private let clock: any VaultClock
    private let passcode: @MainActor () -> PasscodeState
    private let vaultExists: @MainActor () -> Bool
    private let vaultIsEmpty: @MainActor () throws -> Bool
    private let protectedDataAvailable: @MainActor () -> Bool

    private var hasBeenActive = false
    private var backgroundedAt: Date?
    private var waitingForProtectedData = false
    private var leftForegroundDuringPrompt = false
    private var failuresInARow = 0
    /// Bumped by every lock, so an attempt that was waiting for the vault can tell it lost.
    private var lockCount = 0
    private var scanInProgress: ScanSource?
    /// A lock dropped a scan; told once, after the next unlock.
    private var scanDroppedByLock: ScanSource?
    private var shareSheetUp = false
    /// A lock came while the share sheet was up; told once, after the next unlock.
    private var shareStoppedByLock = false
    /// The vault opened while the app was inactive, as after a Face ID prompt: the cover keeps its lock
    /// screen until the app is active, so an unlock never flashes the open cover.
    private(set) var holdsLockScreen = false
    /// While the welcome's choice creates the vault, so the welcome stays up instead of the lock cover.
    private(set) var isCreatingVault = false
    /// Any create, also after "Mulai vault baru", so a lock before anything was written leaves the welcome.
    private var creating = false
    /// Chosen on the welcome screen. Nothing was scanned yet, so a lock drops it without a notice.
    private var pendingScan: ScanSource?

    #if DEBUG
        /// For the device checks: each open attempt and lock event, as statuses only.
        private(set) var attemptLog: [String] = []

        /// For a device check whose screen a lock closes, so its result still reaches the report.
        func log(_ line: String) { attemptLog.append(line) }
    #endif

    init(
        vault: any VaultOpening, clock: any VaultClock = SystemClock(), autoLock: AutoLock = .oneMinute,
        settings: UserDefaults = .standard,
        passcode: @escaping @MainActor () -> PasscodeState = { PasscodeState.current() },
        vaultExists: @escaping @MainActor () -> Bool,
        vaultIsEmpty: @escaping @MainActor () throws -> Bool,
        protectedDataAvailable: @escaping @MainActor () -> Bool
    ) {
        self.vault = vault
        self.clock = clock
        self.autoLock = autoLock
        self.settings = settings
        self.passcode = passcode
        self.vaultExists = vaultExists
        self.vaultIsEmpty = vaultIsEmpty
        self.protectedDataAvailable = protectedDataAvailable
        // Decided now rather than on the first activation, so the first frame never shows the lock cover.
        if protectedDataAvailable(), passcode() != .notSet, isKnownEmpty { state = .noVault }
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
        holdsLockScreen = false
        let returning = !hasBeenActive || backgroundedAt != nil
        hasBeenActive = true
        if let backgroundedAt, state == .unlocked, clock.now.timeIntervalSince(backgroundedAt) >= relockTimeout {
            await lock()
        }
        backgroundedAt = nil
        // From the welcome too: it promises a passcode lock, and the passcode may have gone meanwhile.
        if returning, state == .locked || state == .noVault || retriesOnReturn { await unlock() }
    }

    /// Saves the Kunci otomatis choice and applies it at once, so the stored choice and the
    /// running lock can't drift apart.
    func setAutoLock(_ choice: AutoLock) {
        choice.store(in: settings)
        autoLock = choice
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
        // Opening would create the vault, so the welcome comes first. A folder that can't be read may
        // hold documents, so only a folder known to be empty counts.
        if isKnownEmpty {
            state = .noVault
            return
        }
        await open()
    }

    /// From the welcome screen, or after "Mulai vault baru". `scan` is what the list starts once it shows.
    func createVault(then scan: ScanSource?) async {
        guard state != .unlocking, state != .unlocked else { return }
        // Again, right before the key is made: the passcode may have gone since the welcome showed.
        if let screen = RecoveryMapping.beforeOpening(passcode: passcode(), vaultExists: vaultExists()) {
            state = .recovery(screen)
            return
        }
        pendingScan = scan
        // Only from the welcome, so the welcome stays up; after "Mulai vault baru" the lock screen shows, as
        // for any open.
        isCreatingVault = state == .noVault
        creating = true
        await open(creating: true)
        creating = false
        isCreatingVault = false
        if state != .unlocked { pendingScan = nil }
    }

    /// The scan chosen on the welcome screen, handed over once.
    func takePendingScan() -> ScanSource? {
        defer { pendingScan = nil }
        return pendingScan
    }

    private var isKnownEmpty: Bool { (try? vaultIsEmpty()) == true }

    /// Nothing was open, so a lock on the welcome, or during a create that wrote nothing yet, keeps the
    /// welcome rather than drawing the lock screen on a phone with no vault.
    private var welcomeAfterLock: Bool { (state == .noVault || creating) && isKnownEmpty }

    /// `creating`: making a vault shows no prompt, so a retry would only land back on the welcome and hide the
    /// error; the first failure counts as the last.
    private func open(creating: Bool = false) async {
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
            state = welcomeAfterLock ? .noVault : .locked
            return
        }
        let outcome = RecoveryMapping.outcome(
            of: result, passcode: passcode(),
            failuresInARow: creating ? RecoveryMapping.failuresBeforeGivingUp - 1 : failuresInARow,
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

    /// The scan flow says when a scan starts and ends, so a lock in between can be told after unlocking.
    func scanStarted(_ source: ScanSource) { scanInProgress = source }

    func scanEnded() { scanInProgress = nil }

    /// While the share sheet is up its copies can still be on their way, so a lock then is told.
    func shareSheetShown() { shareSheetUp = true }

    func shareSheetEnded() { shareSheetUp = false }

    func lock() async {
        lockCount += 1
        await vault.lock()
        state = welcomeAfterLock ? .noVault : .locked
        notices = []
        // Locking removes every screen, a scan in progress with it; say so after unlocking.
        if let scanInProgress { scanDroppedByLock = scanInProgress }
        scanInProgress = nil
        if shareSheetUp { shareStoppedByLock = true }
        shareSheetUp = false
        pendingScan = nil
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
            switch scanDroppedByLock {
            case .camera: self.notices = notices.union([.scanDropped])
            case .photos: self.notices = notices.union([.photosDropped])
            case nil: self.notices = notices
            }
            if shareStoppedByLock { self.notices.insert(.shareStopped) }
            scanDroppedByLock = nil
            shareStoppedByLock = false
            // Only while inactive, which always ends with an activation. Recording covers an active app,
            // so a hold set then would never be cleared.
            holdsLockScreen = coverShown
            state = .unlocked
        case .lockCover:
            // A create that didn't finish leaves nothing behind, so the welcome is still the way in.
            state = isKnownEmpty ? .noVault : .locked
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
