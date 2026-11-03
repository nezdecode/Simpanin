//
//  LockCoverView.swift
//  Simpanin
//
//  Created by Inez Amanda on 14/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

/// Covers everything while the vault is locked or the content must be hidden. Shows "Buka" when
/// locked, and the recovery screen when there is one.
struct LockCoverView: View {
    let vault: AppVault
    let lock: LockController

    var body: some View {
        if case .recovery(let screen) = lock.state {
            RecoveryView(screen: screen, vault: vault, lock: lock)
        } else if lock.state == .noVault || lock.isCreatingVault {
            WelcomeView(lock: lock)
        } else {
            LockedView(lock: lock)
        }
    }
}
