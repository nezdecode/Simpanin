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
    /// Background time asked for while a lock "Langsung" started on leaving still waits for the store.
    @State private var backgroundTasks: [UIBackgroundTaskIdentifier] = []

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
        // Locking removes every screen at once, a scan or a share in progress included, before it can tidy
        // up; the page images VisionKit keeps in Caches and the shared copies in tmp are removed here.
        .onChange(of: lock.state) { _, state in
            #if DEBUG
                lock.log("state change seen: \(scenePhase == .background ? "away" : "active")")
            #endif
            if state != .unlocked { LockCleanup.live(in: windowScene).run() }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            switch phase {
            case .active: Task { await lock.sceneDidBecomeActive() }
            case .inactive: lock.sceneDidBecomeInactive()
            case .background:
                if let locking = lock.sceneDidEnterBackground() { keepRunning(until: locking) }
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

    /// iOS suspends an app a few seconds after it leaves, and a save still being written can hold the lock past
    /// that. The cleanup runs here as well, as nothing shows that SwiftUI updates the views in the background.
    private func keepRunning(until locking: Task<Void, Never>) {
        let id = UIApplication.shared.beginBackgroundTask(withName: "Lock") {
            for id in backgroundTasks { endBackgroundTask(id) }
        }
        backgroundTasks.append(id)
        Task {
            await locking.value
            LockCleanup.live(in: windowScene).run { endBackgroundTask(id) }
        }
    }

    /// Once only for each id: iOS ends an app whose background time runs out without being ended.
    private func endBackgroundTask(_ id: UIBackgroundTaskIdentifier) {
        guard let index = backgroundTasks.firstIndex(of: id) else { return }
        backgroundTasks.remove(at: index)
        UIApplication.shared.endBackgroundTask(id)
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
