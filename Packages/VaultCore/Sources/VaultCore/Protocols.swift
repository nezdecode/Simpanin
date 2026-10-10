//
//  Protocols.swift
//  VaultCore
//
//  Created by Inez Amanda on 4/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Crypto
import Foundation

// MARK: - KeyStore

/// What a key store reports when it cannot return the vault key.
public enum KeyStoreError: Error, Equatable, Sendable {
    /// The item definitely does not exist (Keychain errSecItemNotFound, -25300).
    /// This is the only error that allows creating a new vault key.
    case itemNotFound
    /// An item for this vault already exists. It was left as it was.
    case itemAlreadyExists
    /// Any other failure, like a locked device or a cancelled prompt. The key exists but
    /// can't be read right now.
    case unavailable(status: Int32)
}

/// Holds the vault key. The app uses the Keychain, and tests use an in-memory store.
public protocol KeyStore: Sendable {
    /// Returns the vault key. Throw `KeyStoreError.itemNotFound` only when the item doesn't
    /// exist, and a different error for every other failure.
    func readVaultKey(for vaultID: VaultID) async throws -> SymmetricKey

    /// Generates and stores a new random 256-bit vault key. If an item already exists, fail
    /// with `.itemAlreadyExists` instead of overwriting it.
    func createVaultKey(for vaultID: VaultID) async throws -> SymmetricKey

    func deleteVaultKey(for vaultID: VaultID) async throws
}

// MARK: - VaultClock

/// The current time, injected so the 30-day purge and orphan cleanup can be tested.
public protocol VaultClock: Sendable {
    var now: Date { get }
}

public struct SystemClock: VaultClock {
    public init() {}
    public var now: Date { Date() }
}

// MARK: - File protection seam

public enum FileProtectionClass: Sendable {
    /// NSFileProtectionComplete, for vault.json, the index files and page files.
    case complete
    /// completeUntilFirstUserAuthentication, for projection.json, which background tasks read.
    case completeUntilFirstUserAuthentication
}

/// Applies a Data Protection class after every file write. The app implements it.
public protocol FileProtector: Sendable {
    func protect(_ url: URL, as protection: FileProtectionClass) throws
}

/// For tests and macOS, where Data Protection classes do not apply.
public struct NoFileProtection: FileProtector {
    public init() {}
    public func protect(_ url: URL, as protection: FileProtectionClass) throws {}
}
