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

import OSLog
import SwiftUI

@main
struct SimpaninApp: App {
    /// The one VaultStore, made here once. Nothing else creates one for the real vault.
    private let vault: Result<AppVault, any Error> = {
        let result = Result { try AppVault.launch() }
        if case .failure(let error) = result {
            // Domain and code only; a file system error's message can hold paths.
            let error = error as NSError
            Logger(subsystem: "com.inez.Simpanin", category: "launch")
                .error("Setup failed: \(error.domain, privacy: .public) \(error.code, privacy: .public)")
        }
        return result
    }()

    var body: some Scene {
        WindowGroup {
            if let vault = try? vault.get() {
                RootView(vault: vault)
            } else {
                // A broken build (missing entitlements or Info.plist values) or a file system error.
                ContentUnavailableView("setup.failed", systemImage: "exclamationmark.triangle")
            }
        }
    }
}
