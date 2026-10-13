//
//  AppVault.swift
//  Simpanin
//
//  Created by Inez Amanda on 14/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Crypto
import Foundation
import VaultCore

/// Where the vault lives: the vault and old vaults in Application Support, the projection in
/// the App Group, where reminders and widgets can read it.
nonisolated struct VaultLocations: Equatable, Sendable {
    let root: URL
    let quarantine: URL
    let projection: URL

    init(applicationSupport: URL, appGroupContainer: URL) {
        root = applicationSupport.appending(path: "Vault", directoryHint: .isDirectory)
        quarantine = applicationSupport.appending(path: "Quarantine", directoryHint: .isDirectory)
        projection = appGroupContainer.appending(path: "projection.json")
    }
}

/// The app's one VaultStore. `SimpaninApp` makes it once at launch; VaultStore's shared open
/// only protects a single instance per vault folder, so nothing else may create one.
nonisolated final class AppVault: Sendable {
    enum SetupError: Error {
        /// Info.plist lacks the Keychain group or App Group, or the entitlement is missing.
        case missingConfiguration
    }

    let store: VaultStore
    let locations: VaultLocations

    private init(store: VaultStore, locations: VaultLocations) {
        self.store = store
        self.locations = locations
    }

    static func live() throws -> AppVault {
        guard let accessGroup = AppConfiguration.keychainAccessGroup, let appGroup = AppConfiguration.appGroup,
            let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
        else { throw SetupError.missingConfiguration }
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let locations = VaultLocations(applicationSupport: support, appGroupContainer: container)
        let store = VaultStore(
            rootDirectory: locations.root, projectionURL: locations.projection,
            keyStore: KeychainKeyStore(accessGroup: accessGroup), fileProtector: DataProtectionFileProtector())
        return AppVault(store: store, locations: locations)
    }

    #if DEBUG
        /// For previews: its own temp folder and an in-memory key, never the real vault.
        static func preview() -> AppVault {
            let base = FileManager.default.temporaryDirectory.appending(
                path: "SimpaninPreview-\(UUID().uuidString)", directoryHint: .isDirectory)
            let locations = VaultLocations(
                applicationSupport: base, appGroupContainer: base.appending(path: "Group", directoryHint: .isDirectory))
            let store = VaultStore(
                rootDirectory: locations.root, projectionURL: locations.projection, keyStore: PreviewKeyStore(),
                fileProtector: NoFileProtection())
            return AppVault(store: store, locations: locations)
        }
    #endif
}

#if DEBUG
    /// Keeps vault keys in memory, for previews and tests.
    actor PreviewKeyStore: KeyStore {
        private var keys: [VaultID: SymmetricKey] = [:]

        func readVaultKey(for vaultID: VaultID) async throws -> SymmetricKey {
            guard let key = keys[vaultID] else { throw KeyStoreError.itemNotFound }
            return key
        }

        func createVaultKey(for vaultID: VaultID) async throws -> SymmetricKey {
            guard keys[vaultID] == nil else { throw KeyStoreError.itemAlreadyExists }
            let key = SymmetricKey(size: .bits256)
            keys[vaultID] = key
            return key
        }

        func deleteVaultKey(for vaultID: VaultID) async throws {
            guard keys.removeValue(forKey: vaultID) != nil else { throw KeyStoreError.itemNotFound }
        }
    }
#endif
