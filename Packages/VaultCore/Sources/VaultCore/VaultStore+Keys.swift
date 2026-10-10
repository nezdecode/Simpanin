//
//  VaultStore+Keys.swift
//  VaultCore
//
//  Created by Inez Amanda on 10/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Crypto
import Foundation

extension VaultStore {
    // MARK: - Keys

    func readHeader(at url: URL) throws -> VaultHeader {
        struct VersionProbe: Decodable { var formatVersion: Int }
        guard let data = try? Data(contentsOf: url),
            let probe = try? VaultJSON.decoder.decode(VersionProbe.self, from: data)
        else {
            throw VaultError.corruptFile
        }
        guard probe.formatVersion <= VaultHeader.currentFormatVersion else { throw VaultError.unsupportedVersion }
        guard let header = try? VaultJSON.decoder.decode(VaultHeader.self, from: data) else {
            throw VaultError.corruptFile
        }
        return header
    }

    /// The vault exists, so a missing key is an error, never a reason to create one.
    func readExistingVaultKey(_ vaultID: VaultID) async throws -> SymmetricKey {
        do {
            return try await keyStore.readVaultKey(for: vaultID)
        } catch KeyStoreError.itemNotFound {
            throw VaultError.vaultKeyMissing
        } catch {
            throw Self.unavailable(error)
        }
    }

    /// For a new vault: create a key only when the key store reports it does not exist.
    func readOrCreateNewVaultKey(_ vaultID: VaultID) async throws -> SymmetricKey {
        do {
            return try await keyStore.readVaultKey(for: vaultID)
        } catch KeyStoreError.itemNotFound {
            do {
                return try await keyStore.createVaultKey(for: vaultID)
            } catch {
                throw Self.unavailable(error)
            }
        } catch {
            throw Self.unavailable(error)
        }
    }

    /// Keeps the Keychain status so the app can tell "passcode turned off" (-25293) apart.
    static func unavailable(_ error: any Error) -> VaultError {
        if case KeyStoreError.unavailable(let status) = error {
            return .vaultKeyUnavailable(status: status)
        }
        return .vaultKeyUnavailable(status: nil)
    }

}
