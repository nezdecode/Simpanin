//
//  PreviewKeyStore.swift
//  Simpanin
//
//  Created by Inez Amanda on 14/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

#if DEBUG
    import Crypto
    import Foundation
    import VaultCore

    /// Keeps vault keys in memory, for previews and tests.
    actor PreviewKeyStore {
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

    // In an extension, like the actors in UITestSetup: a conformance declared on an actor can trip a Swift 6.4
    // bug that depends on the order files are type-checked in.
    extension PreviewKeyStore: KeyStore {}
#endif
