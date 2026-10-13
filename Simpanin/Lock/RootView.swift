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
        let header = vault.locations.root.appending(path: "vault.json")
        _lock = State(
            initialValue: LockController(
                vault: vault.store,
                vaultExists: { FileManager.default.fileExists(atPath: header.path) },
                protectedDataAvailable: { UIApplication.shared.isProtectedDataAvailable }))
    }

    var body: some View {
        ContentView(vault: vault)
            .overlay {
                if lock.contentHidden { LockCoverView(lock: lock) }
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

/// The lock cover. Part 4 replaces the placeholder recovery text with the real screens.
struct LockCoverView: View {
    let lock: LockController

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.fill").font(.largeTitle)
            if case .recovery(let screen) = lock.state {
                Text(String(describing: screen)).font(.footnote).foregroundStyle(.secondary)
            }
            if lock.state != .unlocking {
                Button("Buka") { Task { await lock.unlock() } }
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }
}
