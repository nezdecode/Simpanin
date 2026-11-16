//
//  AppSetup.swift
//  Simpanin
//
//  Created by Inez Amanda on 16/11/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import OSLog
import Observation

/// Makes the app's one AppVault, and with it the one VaultStore. A launch can fail to set it up, for example
/// before the phone's first unlock, so it's tried again whenever the scene comes forward and from Coba lagi.
@MainActor @Observable
final class AppSetup {
    private(set) var vault: AppVault?
    @ObservationIgnored private let launch: @MainActor () throws -> AppVault
    @ObservationIgnored private let cleanUp: @MainActor () -> Void
    @ObservationIgnored private var cleanedUp = false

    init(
        launch: @escaping @MainActor () throws -> AppVault = AppVault.launch,
        cleanUp: @escaping @MainActor () -> Void = cleanUpLeftovers
    ) {
        self.launch = launch
        self.cleanUp = cleanUp
        retry()
    }

    /// Stays synchronous on the main actor: two attempts can't overlap, which is what keeps it to one VaultStore.
    func retry() {
        guard vault == nil else { return }
        do {
            vault = try launch()
        } catch {
            Logger.launch.error("Setup failed: \(ErrorSummary.describe(error), privacy: .public)")
        }
    }

    /// The leftovers are removed once, at the first activation, when the phone is sure to be unlocked. Never
    /// again: a later activation can return to a scan in progress, whose pages are in the camera's folder.
    func sceneDidBecomeActive() {
        if !cleanedUp {
            cleanedUp = true
            cleanUp()
        }
        retry()
    }

    func sceneDidBecomeInactive() { retry() }

    /// The app may have been stopped during a scan or a share, before their copies were removed.
    static func cleanUpLeftovers() {
        DocumentCameraCache.clear()
        SharedCopies.clear()
    }
}
