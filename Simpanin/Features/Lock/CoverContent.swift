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
    /// "Terkunci", with Buka when the vault is locked.
    case lockScreen
    /// The vault is open but covered: Control Centre, a call, the app switcher, a permission question.
    case nameOnly
    /// The vault is open while the screen is recorded or mirrored, a lasting state, so it says why.
    case recording

    init(state: LockController.State, isCreatingVault: Bool, screenCaptured: Bool, holdsLockScreen: Bool) {
        switch state {
        case .recovery(let screen): self = .recovery(screen)
        // Nothing private on the welcome, so it shows as it is, in the app switcher and while recording.
        case _ where isCreatingVault, .noVault: self = .welcome
        case .locked, .unlocking: self = .lockScreen
        case .unlocked where holdsLockScreen: self = .lockScreen
        case .unlocked: self = screenCaptured ? .recording : .nameOnly
        }
    }
}

extension CoverContent {
    @MainActor init(_ lock: LockController) {
        self.init(
            state: lock.state, isCreatingVault: lock.isCreatingVault, screenCaptured: lock.screenCaptured,
            holdsLockScreen: lock.holdsLockScreen)
    }
}
