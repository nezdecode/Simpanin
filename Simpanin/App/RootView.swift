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
import VaultCore

/// Connects the system events from the lifecycle table to the LockController and covers the
/// content whenever it must be hidden.
struct RootView: View {
    let vault: AppVault
    @State private var lock: LockController
    @Environment(\.scenePhase) private var scenePhase
    @State private var cover: CoverWindow<LockCoverView>
    @State private var windowScene: UIWindowScene?

    init(vault: AppVault) {
        self.vault = vault
        let lock = Self.makeLock(for: vault)
        _lock = State(initialValue: lock)
        _cover = State(initialValue: CoverWindow(LockCoverView(vault: vault, lock: lock)))
    }

    static func makeLock(for vault: AppVault, defaults: UserDefaults = .standard) -> LockController {
        #if DEBUG
            if UITestSetup.isActive { return UITestSetup.lockController(for: vault) }
        #endif
        return LockController(
            vault: vault.store,
            autoLock: AutoLock.stored(in: defaults), settings: defaults,
            vaultExists: { VaultStore.vaultExists(in: vault.locations.root) },
            vaultIsEmpty: { try VaultStore.isEmpty(in: vault.locations.root) },
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
        // Until the window scene is known, the first frame, the cover is drawn here as before.
        .overlay {
            if lock.contentHidden, windowScene == nil { LockCoverView(vault: vault, lock: lock) }
        }
        .background(WindowSceneReader { windowScene = $0 })
        .onChange(of: lock.contentHidden, initial: true) { _, hidden in showCover(hidden) }
        .onChange(of: windowScene) { _, scene in
            if let scene { cover.watchCapture(in: scene) { lock.screenCaptured = $0 } }
            showCover(lock.contentHidden)
        }
        // Locking removes every screen at once, a scan in progress included, before it can tidy up; the
        // page images VisionKit keeps in Caches are removed here, which outlives them.
        .onChange(of: lock.state) { _, state in
            if state != .unlocked { DocumentCameraCache.clear() }
        }
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

    private func showCover(_ hidden: Bool) {
        guard let windowScene else { return }
        if hidden {
            cover.show(in: windowScene)
        } else {
            cover.hide()
        }
    }
}
