//
//  SimpaninApp.swift
//  Simpanin
//
//  Created by Inez Amanda on 4/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

@main
struct SimpaninApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    /// Makes the one VaultStore. Nothing else creates one for the real vault.
    @State private var setup: AppSetup

    init() {
        #if DEBUG
            let launch: @MainActor () throws -> AppVault =
                UITestSetup.isActive ? UITestSetup.setupLauncher() : AppVault.launch
        #else
            let launch = AppVault.launch
        #endif
        _setup = State(initialValue: AppSetup(launch: launch))
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let vault = setup.vault {
                    RootView(vault: vault)
                } else {
                    // A broken build (missing entitlements or Info.plist values) or a file system error.
                    LoadFailedView(title: "setup.failed") { setup.retry() }
                }
            }
            .background(ScenePhaseWatcher(setup: setup))
        }
    }
}

/// Passes the scene's phase on to AppSetup. It's read here, not in SimpaninApp, whose body would otherwise run
/// again at every change and rebuild RootView, with a LockController it then throws away.
private struct ScenePhaseWatcher: View {
    let setup: AppSetup
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Color.clear
            .accessibilityHidden(true)
            .onChange(of: scenePhase, initial: true) { _, phase in
                switch phase {
                case .active: setup.sceneDidBecomeActive()
                case .inactive: setup.sceneDidBecomeInactive()
                default: break
                }
            }
    }
}
