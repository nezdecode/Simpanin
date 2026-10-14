//
//  RootView.swift
//  Simpanin
//
//  Created by Inez Amanda on 14/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI
import UIKit

/// Connects the system events from the lifecycle table to the LockController and covers the
/// content whenever it must be hidden.
struct RootView: View {
    let vault: AppVault
    @State private var lock: LockController
    @Environment(\.scenePhase) private var scenePhase

    init(vault: AppVault) {
        self.vault = vault
        _lock = State(initialValue: Self.makeLock(for: vault))
    }

    static func makeLock(for vault: AppVault, defaults: UserDefaults = .standard) -> LockController {
        #if DEBUG
            if UITestSetup.isActive { return UITestSetup.lockController(for: vault) }
        #endif
        let header = vault.locations.root.appending(path: "vault.json")
        return LockController(
            vault: vault.store,
            relockTimeout: AutoLock.stored(in: defaults).seconds,
            vaultExists: { FileManager.default.fileExists(atPath: header.path) },
            protectedDataAvailable: { UIApplication.shared.isProtectedDataAvailable })
    }

    var body: some View {
        Group {
            if lock.state == .unlocked {
                LibraryView(vault: vault, lock: lock)
            } else {
                Color.clear
            }
        }
        .overlay {
            if lock.contentHidden { LockCoverView(vault: vault, lock: lock) }
        }
        .background(SceneCaptureReader { lock.screenCaptured = $0 })
        .onChange(of: scenePhase, initial: true) { _, phase in
            switch phase {
            case .active: Task { await lock.sceneDidBecomeActive() }
            case .inactive: lock.sceneDidBecomeInactive()
            case .background: lock.sceneDidEnterBackground()
            @unknown default: break
            }
        }
        .task {
            let name = UIApplication.protectedDataWillBecomeUnavailableNotification
            for await _ in NotificationCenter.default.notifications(named: name) {
                await lock.protectedDataWillBecomeUnavailable()
            }
        }
        .task {
            let name = UIApplication.protectedDataDidBecomeAvailableNotification
            for await _ in NotificationCenter.default.notifications(named: name) {
                await lock.protectedDataDidBecomeAvailable()
            }
        }
    }
}
