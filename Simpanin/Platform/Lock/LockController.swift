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
    /// A store that is busy with a write answers a lock late, and `state` changes only then, so a lock still
    /// waiting hides the content from the moment it is decided.
    var contentHidden: Bool { state != .unlocked || coverShown || screenCaptured || sequence.locksWaiting > 0 }
    private let sequence = LockSequence()

    /// A lock or an open still runs, so the lock screen holds Buka back, and shows that it waits once it has lasted.
    var isBusy: Bool { sequence.isBusy }
    var showsWaiting: Bool { sequence.showsWaiting }

    /// The one place the Kunci otomatis choice lives while the app runs; Settings reads it here,
    /// so the screen can't show a different choice than the lock uses.
    private(set) var autoLock: AutoLock
    /// Where the choice is saved. UI tests pass their own store, so they never touch the app's.
    private let settings: UserDefaults
    var relockTimeout: TimeInterval { autoLock.seconds }
    /// The same check the lock uses, so "+" can ask for a passcode before the first scan.
    var passcodeState: PasscodeState { passcode() }
    private let vault: any VaultOpening
    /// A clock that can't be set and keeps counting while the phone sleeps: the phone's date can be changed in
    /// Settings with no passcode, so it must not decide how long the vault stays open.
    private let now: @MainActor () -> ContinuousClock.Instant
    private let passcode: @MainActor () -> PasscodeState
    private let vaultExists: @MainActor () -> Bool
    private let vaultIsEmpty: @MainActor () throws -> Bool
    private let protectedDataAvailable: @MainActor () -> Bool

    private var hasBeenActive = false
    /// Counts returns from the background, so of two waiting at once only the latest prompts.
    @ObservationIgnored private var returns = 0
    private var backgroundedAt: ContinuousClock.Instant?
    private var waitingForProtectedData = false
    private var leftForegroundDuringPrompt = false
    private var failuresInARow = 0
    /// Bumped by every lock, so an attempt that was waiting for the vault can tell it lost.
    private var lockCount = 0
    private var work = WorkInProgress()
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
        vault: any VaultOpening, now: @escaping @MainActor () -> ContinuousClock.Instant = { ContinuousClock.now },
        autoLock: AutoLock = .oneMinute, settings: UserDefaults = .standard,
        passcode: @escaping @MainActor () -> PasscodeState = { PasscodeState.current() },
        vaultExists: @escaping @MainActor () -> Bool,
        vaultIsEmpty: @escaping @MainActor () throws -> Bool,
        protectedDataAvailable: @escaping @MainActor () -> Bool
    ) {
        self.vault = vault
        self.now = now
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
        if returning { returns += 1 }
        let trip = returns
        // Cleared before the lock, not after: the app can go to the background again while the store answers.
        // That trip keeps its own start, and the prompt waits for the return, as none can show in the background.
        let awaySince = backgroundedAt
        backgroundedAt = nil
        // Decided before the wait: the wait can span someone else's whole open, and with "Langsung" the time is
        // always out, so a later check would lock a vault just opened. An open still running loses to this lock,
        // as at a leave, so its keys aren't kept past the timeout; a lock already waiting locks anyway.
        let open = state == .unlocked || state == .unlocking
        if let awaySince, open, sequence.locksWaiting == 0, timedOut(since: awaySince) { _ = startLock() }
        // Every lock already decided lands first, the leave's among them, and the open in flight ends, so this
        // return neither prompts ahead of them nor joins an open a lock has lost.
        await sequence.settle()
        // A later return waited too, and prompts for both: one that went first would ask again after a Batal.
        guard backgroundedAt == nil, trip == returns else { return }
        // From the welcome too: it promises a passcode lock, and the passcode may have gone meanwhile.
        if returning, state == .locked || state == .noVault || retriesOnReturn { await unlock() }
    }

    /// Any time away outside zero up to the timeout locks, so a time that comes out negative never keeps
    /// the vault open.
    private func timedOut(since start: ContinuousClock.Instant) -> Bool {
        !(.zero ..< .seconds(relockTimeout)).contains(start.duration(to: now()))
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
    /// "Langsung" locks here instead, so no keys wait in a suspended app. The lock is decided before anything else
    /// runs, so an open whose result is already on its way is dropped. The task is the store's half, for the app to
    /// keep running until it lands.
    @discardableResult
    func sceneDidEnterBackground() -> Task<Void, Never>? {
        coverShown = true
        backgroundedAt = now()
        if state == .unlocking { leftForegroundDuringPrompt = true }
        // The cover, the welcome and the recovery screens hold no keys, and a lock would replace a recovery screen.
        guard autoLock == .immediately, state == .unlocked || state == .unlocking else { return nil }
        let task = startLock()
        #if DEBUG
            Task { [weak self] in
                await task.value
                if let self {
                    attemptLog.append("leave lock landed: \(backgroundedAt == nil ? "after return" : "away")")
                }
            }
        #endif
        return task
    }

    func protectedDataWillBecomeUnavailable() async {
        #if DEBUG
            attemptLog.append("phone locked")
        #endif
        await lock()
    }

    func protectedDataDidBecomeAvailable() async {
        guard waitingForProtectedData else { return }
        // Cleared either way, so a stale one can't prompt at some later phone unlock. Face ID can't show in the
        // background, and the return prompts from the lock screen anyway.
        waitingForProtectedData = false
        guard backgroundedAt == nil else { return }
        await unlock()
    }

    // MARK: - Unlock and lock

    /// From the lock cover's "Buka" button, a recovery screen's retry, or by itself.
    func unlock() async {
        await sequence.settle()
        guard state != .unlocking, state != .unlocked else { return }
        await sequence.open { [weak self] in await self?.unlockSteps() }
    }

    /// The checks before an open, then the open, again for as long as the outcome asks for another prompt; all one
    /// open, so a retry never waits for itself.
    private func unlockSteps() async {
        repeat {
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
        } while await open()
    }

    /// From the welcome screen, or after "Mulai vault baru". `scan` is what the list starts once it shows.
    func createVault(then scan: ScanSource?) async {
        let screen = state
        await sequence.settle()
        // Only from the screen the tap came from, the welcome or a recovery screen, and only if it's still there.
        // A lock puts the lock screen in its place, as when the phone locks while "Mulai vault baru" moves the old
        // vault aside, and a create that failed meanwhile leaves its error screen, which no tap asked for again.
        guard state == screen else { return }
        switch screen {
        case .noVault, .recovery: break
        case .locked, .unlocking, .unlocked: return
        }
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
        await sequence.open { [weak self] in await self?.open(creating: true) }
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
    /// error; the first failure counts as the last. True when the outcome asks for the prompt again.
    @discardableResult
    private func open(creating: Bool = false) async -> Bool {
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
            return false
        }
        // An open can start after the app left, like a create after "Mulai vault baru" or a late welcome tap.
        // With "Langsung" its keys mustn't stay while the app is away. A failed one holds none and keeps its screen.
        if case .success = result, backgroundedAt != nil, autoLock == .immediately {
            #if DEBUG
                attemptLog.append("open: \(Self.describe(result)) -> locked, app away")
            #endif
            await lock()
            return false
        }
        let outcome = RecoveryMapping.outcome(
            of: result, passcode: passcode(),
            failuresInARow: creating ? RecoveryMapping.failuresBeforeGivingUp - 1 : failuresInARow,
            leftForegroundDuringPrompt: leftForegroundDuringPrompt)
        #if DEBUG
            attemptLog.append("open: \(Self.describe(result)) -> \(outcome)")
        #endif
        return apply(outcome)
    }

    /// Notices are shown once: dismissing one hides it until the next open reports it again.
    func dismiss(_ notice: VaultNotice) {
        notices.remove(notice)
    }

    /// The scan flow says when a scan starts and ends, so a lock in between can be told after unlocking.
    func scanStarted(_ source: ScanSource) { work.scanInProgress = source }

    func scanEnded() { work.scanInProgress = nil }

    /// While the share sheet is up its copies can still be on their way, so a lock then is told.
    func shareSheetShown() { work.shareSheetUp = true }

    func shareSheetEnded() { work.shareSheetUp = false }

    /// Edit dokumen says whether it holds changes not saved yet, so a lock then can be told after unlocking.
    func editChanged(_ unsaved: Bool) { work.editUnsaved = unsaved }

    func lock() async {
        await startLock().value
    }

    /// Decided at once, so an open still waiting can tell it lost and the content is hidden; the store's half runs
    /// after every earlier lock. The task is that half.
    private func startLock() -> Task<Void, Never> {
        lockCount += 1
        return sequence.lock { [weak self] in await self?.finishLock() }
    }

    private func finishLock() async {
        await vault.lock()
        state = welcomeAfterLock ? .noVault : .locked
        notices = []
        work.lockLanded()
        pendingScan = nil
        failuresInARow = 0
    }

    /// True when the prompt should come again.
    private func apply(_ outcome: LockOutcome) -> Bool {
        switch outcome {
        case .unlocked(let notices):
            failuresInARow = 0
            self.notices = notices.union(work.takeNotices())
            // Only while inactive, which always ends with an activation. Recording covers an active app,
            // so a hold set then would never be cleared.
            holdsLockScreen = coverShown
            state = .unlocked
            return false
        case .lockCover:
            // A create that didn't finish leaves nothing behind, so the welcome is still the way in.
            state = isKnownEmpty ? .noVault : .locked
            return false
        case .promptAgain:
            failuresInARow += 1
            state = .locked
            return true
        case .recovery(let screen):
            // A retry from the screen starts a fresh count.
            failuresInARow = 0
            state = .recovery(screen)
            return false
        }
    }
}

#if DEBUG
    extension LockController {
        /// Statuses only: VaultError cases carry no ids or values, other errors show their type.
        private static func describe(_ result: Result<OpenReport, any Error>) -> String {
            switch result {
            case .success: "opened"
            case .failure(let error): ErrorSummary.describe(error)
            }
        }
    }
#endif
