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
    /// The one VaultStore, made here once. Nothing else creates one for the real vault.
    private let vault = Result { try AppVault.launch() }

    var body: some Scene {
        WindowGroup {
            if let vault = try? vault.get() {
                RootView(vault: vault)
            } else {
                // Only a broken build gets here: the entitlements or Info.plist values are missing.
                ContentUnavailableView("setup.failed", systemImage: "exclamationmark.triangle")
            }
        }
    }
}
