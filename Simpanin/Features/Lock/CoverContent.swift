//
//  CoverContent.swift
//  Simpanin
//
//  Created by Inez Amanda on 3/11/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

/// What the cover draws. When it shows is the lock's decision (`contentHidden`); this only keeps it from
/// saying "Terkunci" while the vault is open.
nonisolated enum CoverContent: Equatable {
    case recovery(RecoveryScreen)
    case welcome
    /// "Terkunci", and what its foot offers.
    case lockScreen(Action)
    /// The vault is open but covered: Control Centre, a call, the app switcher, a permission question.
    case nameOnly
    /// The vault is open while the screen is recorded or mirrored, a lasting state, so it says why.
    case recording

    /// What the lock screen offers at its foot.
    enum Action: Equatable {
        /// Buka.
        case open
        /// A lock, or an open that lost to one, has run long enough to show that the screen waits.
        case waiting
        /// Nothing: the Face ID prompt is up, the vault is open behind the cover, or a wait is too short to show.
        case nothing
    }

    init(
        state: LockController.State, isCreatingVault: Bool, screenCaptured: Bool, holdsLockScreen: Bool,
        isBusy: Bool, showsWaiting: Bool
    ) {
        switch state {
        case .recovery(let screen): self = .recovery(screen)
        // Nothing private on the welcome, so it shows as it is, in the app switcher and while recording.
        case _ where isCreatingVault, .noVault: self = .welcome
        // Buka would wait for whatever still runs, so it shows only once nothing does. While unlocking, the Face ID
        // prompt is up, and the open behind it runs as long.
        case .locked where !isBusy: self = .lockScreen(.open)
        case .locked: self = .lockScreen(showsWaiting ? .waiting : .nothing)
        case .unlocking: self = .lockScreen(.nothing)
        case .unlocked where holdsLockScreen: self = .lockScreen(.nothing)
        case .unlocked: self = screenCaptured ? .recording : .nameOnly
        }
    }
}

extension CoverContent {
    @MainActor init(_ lock: LockController) {
        self.init(
            state: lock.state, isCreatingVault: lock.isCreatingVault, screenCaptured: lock.screenCaptured,
            holdsLockScreen: lock.holdsLockScreen, isBusy: lock.isBusy, showsWaiting: lock.showsWaiting)
    }
}
