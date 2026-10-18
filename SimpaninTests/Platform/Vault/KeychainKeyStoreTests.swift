//
//  KeychainKeyStoreTests.swift
//  SimpaninTests
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
import Synchronization
import Testing
import VaultCore

@testable import Simpanin

enum KeychainCallKind: Sendable { case copy, add, delete }

/// Answers every SecItem call with a chosen status and records what each query asked for.
/// Only a summary is kept, so nothing non-Sendable leaves the call.
final class FakeKeychain: KeychainAPI {
    struct Call: Sendable, Equatable {
        let kind: KeychainCallKind
        let itemClass: String?
        let service: String?
        let account: String?
        let accessGroup: String?
        let synchronizable: Bool?
        let hasAccessControl: Bool
        let separateAccessible: Bool
        let reason: String?
        let returnsData: Bool
        let limitOne: Bool
        let valueBytes: Int?
    }

    private let state: Mutex<(status: OSStatus, data: Data?, calls: [Call])>

    init(status: OSStatus = errSecSuccess, data: Data? = nil) {
        state = Mutex((status, data, []))
    }

    var calls: [Call] { state.withLock { $0.calls } }

    private func record(_ kind: KeychainCallKind, _ query: [String: Any]) -> (OSStatus, Data?) {
        let call = Call(
            kind: kind,
            itemClass: query[kSecClass as String] as? String,
            service: query[kSecAttrService as String] as? String,
            account: query[kSecAttrAccount as String] as? String,
            accessGroup: query[kSecAttrAccessGroup as String] as? String,
            synchronizable: query[kSecAttrSynchronizable as String] as? Bool,
            hasAccessControl: query[kSecAttrAccessControl as String] != nil,
            separateAccessible: query[kSecAttrAccessible as String] != nil,
            reason: (query[kSecUseAuthenticationContext as String] as? LAContext)?.localizedReason,
            returnsData: query[kSecReturnData as String] as? Bool == true,
            limitOne: query[kSecMatchLimit as String] as? String == kSecMatchLimitOne as String,
            valueBytes: (query[kSecValueData as String] as? Data)?.count)
        return state.withLock { state in
            state.calls.append(call)
            return (state.status, state.data)
        }
    }

    func copyMatching(_ query: [String: Any]) -> (status: OSStatus, data: Data?) {
        record(.copy, query)
    }

    func add(_ attributes: [String: Any]) -> OSStatus { record(.add, attributes).0 }
    func delete(_ query: [String: Any]) -> OSStatus { record(.delete, query).0 }
}

@Suite("KeychainKeyStore")
struct KeychainKeyStoreTests {
    let vaultID = VaultID(UUID(uuidString: "AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE")!)
    let accessGroup = "TEAMPREFIX.simpanin.vault"

    func store(_ keychain: FakeKeychain) -> KeychainKeyStore {
        KeychainKeyStore(accessGroup: accessGroup, keychain: keychain)
    }

    // MARK: Status mapping (review item V4). Only -25300 means "not found".

    static let otherStatuses: [OSStatus] = [
        -128,  // errSecUserCanceled: "Batal" on the prompt
        -25293,  // errSecAuthFailed: passcode turned off, or authentication failed
        -25308,  // errSecInteractionNotAllowed: the phone is locked
        -25291,  // errSecNotAvailable
        -34018,  // errSecMissingEntitlement
        -50,  // errSecParam
    ]

    @Test func notFoundIsTheOnlyStatusThatMeansMissing() {
        #expect(KeychainKeyStore.error(for: errSecItemNotFound) == .itemNotFound)
        #expect(KeychainKeyStore.error(for: errSecDuplicateItem) == .itemAlreadyExists)
        for status in Self.otherStatuses {
            #expect(KeychainKeyStore.error(for: status) == .unavailable(status: status))
        }
    }

    @Test(arguments: [errSecItemNotFound] + otherStatuses)
    func readMapsEveryFailure(_ status: OSStatus) async throws {
        let keychain = FakeKeychain(status: status)
        await #expect(throws: KeychainKeyStore.error(for: status)) {
            try await store(keychain).readVaultKey(for: vaultID)
        }
        #expect(keychain.calls.map(\.kind) == [.copy])  // never deletes or recreates
    }

    @Test(arguments: [errSecDuplicateItem] + otherStatuses)
    func createMapsEveryFailureAndNeverReplaces(_ status: OSStatus) async throws {
        let keychain = FakeKeychain(status: status)
        await #expect(throws: KeychainKeyStore.error(for: status)) {
            try await store(keychain).createVaultKey(for: vaultID)
        }
        #expect(keychain.calls.map(\.kind) == [.add])
    }

    @Test func deleteMapsNotFound() async throws {
        await #expect(throws: KeyStoreError.itemNotFound) {
            try await store(FakeKeychain(status: errSecItemNotFound)).deleteVaultKey(for: vaultID)
        }
        try await store(FakeKeychain()).deleteVaultKey(for: vaultID)
    }

    // MARK: What each call asks the Keychain for

    @Test func readUsesOneItemAndTheUnevaluatedPromptContext() async throws {
        let bytes = Data((0..<32).map { UInt8($0) })
        let keychain = FakeKeychain(data: bytes)
        let key = try await store(keychain).readVaultKey(for: vaultID)
        #expect(key.withUnsafeBytes { Data($0) } == bytes)
        let call = try #require(keychain.calls.first)
        #expect(call.itemClass == kSecClassGenericPassword as String)
        #expect(call.service == "simpanin.vault")
        #expect(call.account == "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee")
        #expect(call.accessGroup == accessGroup)
        #expect(call.synchronizable == false)
        #expect(call.returnsData && call.limitOne)
        #expect(call.reason == "Buka vault dokumenmu")
    }

    @Test func createAddsAProtectedRandomKey() async throws {
        let keychain = FakeKeychain()
        let first = try await store(keychain).createVaultKey(for: vaultID)
        let second = try await store(keychain).createVaultKey(for: vaultID)
        #expect(first.bitCount == 256)
        #expect(first.withUnsafeBytes { Data($0) } != second.withUnsafeBytes { Data($0) })
        let call = try #require(keychain.calls.first)
        #expect(call.kind == .add)
        #expect(call.service == "simpanin.vault")
        #expect(call.account == "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee")
        #expect(call.accessGroup == accessGroup)
        #expect(call.synchronizable == false)
        #expect(call.hasAccessControl)
        #expect(!call.separateAccessible)  // accessibility lives in the access control only
        #expect(call.valueBytes == 32)
    }

    @Test func deleteTargetsOnlyThisVaultsItem() async throws {
        let keychain = FakeKeychain()
        try await store(keychain).deleteVaultKey(for: vaultID)
        let call = try #require(keychain.calls.first)
        #expect(call.kind == .delete)
        #expect(call.service == "simpanin.vault")
        #expect(call.account == "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee")
        #expect(call.accessGroup == accessGroup)
    }

    @Test func accessControlIsWhenUnlockedThisDeviceOnlyWithUserPresence() {
        #expect(KeychainKeyStore.accessibility == kSecAttrAccessibleWhenUnlockedThisDeviceOnly)
        #expect(KeychainKeyStore.accessControlFlags == .userPresence)
    }

    // MARK: Passcode check, for onboarding and before creating a vault key

    @Test func passcodeState() {
        #expect(PasscodeState.from(canEvaluate: true, error: nil) == .set)
        #expect(PasscodeState.from(canEvaluate: false, error: LAError(.passcodeNotSet)) == .notSet)
        // Another reason doesn't mean the passcode is missing.
        #expect(
            PasscodeState.from(canEvaluate: false, error: LAError(.biometryLockout))
                == .unknown(code: LAError.Code.biometryLockout.rawValue))
    }

    /// Only a passcode known to be off stops a scan. An unknown state tries, and the save says why if the
    /// key really can't be used.
    @Test func onlyAMissingPasscodeStopsAScan() {
        #expect(PasscodeState.notSet.stopsScanning)
        #expect(!PasscodeState.set.stopsScanning)
        #expect(!PasscodeState.unknown(code: LAError.Code.biometryLockout.rawValue).stopsScanning)
    }
}
