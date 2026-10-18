//
//  KeychainKeyStore.swift
//  Simpanin
//
//  Created by Inez Amanda on 13/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Crypto
import Foundation
import LocalAuthentication
import Security
import VaultCore

/// The SecItem calls, behind a protocol so the status mapping is tested without a Keychain.
nonisolated protocol KeychainAPI: Sendable {
    func copyMatching(_ query: [String: Any]) -> (status: OSStatus, data: Data?)
    func add(_ attributes: [String: Any]) -> OSStatus
    func delete(_ query: [String: Any]) -> OSStatus
}

/// The real Keychain.
nonisolated struct SystemKeychain: KeychainAPI {
    func copyMatching(_ query: [String: Any]) -> (status: OSStatus, data: Data?) {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return (status, result as? Data)
    }

    func add(_ attributes: [String: Any]) -> OSStatus {
        SecItemAdd(attributes as CFDictionary, nil)
    }

    func delete(_ query: [String: Any]) -> OSStatus {
        SecItemDelete(query as CFDictionary)
    }
}

/// The vault key, one Keychain item per vault. The service, account and access group must
/// never change once a vault exists, or its key can't be found again.
nonisolated struct KeychainKeyStore: KeyStore {
    static let service = "simpanin.vault"
    /// Readable only while the phone is unlocked, never copied to another device or a backup.
    static var accessibility: CFString { kSecAttrAccessibleWhenUnlockedThisDeviceOnly }
    /// Face ID, or the passcode when Face ID fails or is off. Never a biometry-only flag:
    /// re-enrolling a face would make the key unreadable for good.
    static let accessControlFlags: SecAccessControlCreateFlags = .userPresence
    static let promptReason = "Buka vault dokumenmu"

    let accessGroup: String
    let keychain: any KeychainAPI

    init(accessGroup: String, keychain: any KeychainAPI = SystemKeychain()) {
        self.accessGroup = accessGroup
        self.keychain = keychain
    }

    /// Only -25300 means the item doesn't exist. Every other status means it may exist but
    /// can't be read now, so VaultCore never creates a key for it.
    static func error(for status: OSStatus) -> KeyStoreError {
        switch status {
        case errSecItemNotFound: .itemNotFound
        case errSecDuplicateItem: .itemAlreadyExists
        default: .unavailable(status: status)
        }
    }

    func readVaultKey(for vaultID: VaultID) async throws -> SymmetricKey {
        let (status, data) = await offTheActor {
            // Not evaluated first: the Keychain shows the one prompt itself.
            let context = LAContext()
            context.localizedReason = Self.promptReason
            var query = itemQuery(vaultID)
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            query[kSecUseAuthenticationContext as String] = context
            return keychain.copyMatching(query)
        }
        guard status == errSecSuccess else { throw Self.error(for: status) }
        guard let data else { throw KeyStoreError.unavailable(status: errSecDecode) }
        return SymmetricKey(data: data)
    }

    func createVaultKey(for vaultID: VaultID) async throws -> SymmetricKey {
        let key = SymmetricKey(size: .bits256)
        let bytes = key.withUnsafeBytes { Data($0) }
        let status = await offTheActor {
            guard
                let access = SecAccessControlCreateWithFlags(
                    nil, Self.accessibility, Self.accessControlFlags, nil)
            else { return errSecParam }
            var attributes = itemQuery(vaultID)
            attributes[kSecAttrAccessControl as String] = access
            attributes[kSecValueData as String] = bytes
            return keychain.add(attributes)
        }
        guard status == errSecSuccess else { throw Self.error(for: status) }
        return key
    }

    func deleteVaultKey(for vaultID: VaultID) async throws {
        let status = await offTheActor { keychain.delete(itemQuery(vaultID)) }
        guard status == errSecSuccess else { throw Self.error(for: status) }
    }

    private func itemQuery(_ vaultID: VaultID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: vaultID.string,
            kSecAttrAccessGroup as String: accessGroup,
            kSecAttrSynchronizable as String: false,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }

    /// SecItem calls block while the prompt is up. Running them on a dispatch queue keeps the
    /// caller's actor (the VaultStore) free in the meantime.
    private func offTheActor<T: Sendable>(_ body: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { continuation.resume(returning: body()) }
        }
    }
}
