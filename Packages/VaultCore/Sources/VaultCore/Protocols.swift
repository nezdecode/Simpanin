import Crypto
import Foundation

// MARK: - KeyStore

/// What a key store reports when it cannot return the vault key.
public enum KeyStoreError: Error, Equatable, Sendable {
    /// The item definitely does not exist (Keychain errSecItemNotFound, -25300).
    /// This is the only error that allows creating a new vault key.
    case itemNotFound
    /// An item for this vault already exists; it was not overwritten.
    case itemAlreadyExists
    /// Any other failure (errSecAuthFailed -25293, errSecInteractionNotAllowed -25308,
    /// user cancel...). The key exists but cannot be read now.
    case unavailable(status: Int32)
}

/// Holds the vault key. The app implements it with the Keychain
/// (WhenUnlockedThisDeviceOnly, .userPresence; see the design doc). Tests use an
/// in-memory store.
public protocol KeyStore: Sendable {
    /// Returns the vault key. Throws `KeyStoreError.itemNotFound` only when the item
    /// does not exist; every other failure must be a different error.
    func readVaultKey(for vaultID: VaultID) async throws -> SymmetricKey

    /// Generates and stores a new random 256-bit vault key. Must fail with
    /// `.itemAlreadyExists` rather than overwrite an existing item.
    func createVaultKey(for vaultID: VaultID) async throws -> SymmetricKey

    func deleteVaultKey(for vaultID: VaultID) async throws
}

// MARK: - Clock

/// The current time, injected so the 30-day purge and orphan cleanup can be tested.
public protocol Clock: Sendable {
    var now: Date { get }
}

public struct SystemClock: Clock {
    public init() {}
    public var now: Date { Date() }
}

// MARK: - File protection seam

public enum FileProtectionClass: Sendable {
    /// NSFileProtectionComplete: vault.json, index files, page files.
    case complete
    /// completeUntilFirstUserAuthentication: projection.json, read by background tasks.
    case completeUntilFirstUserAuthentication
}

/// Applies Data Protection classes. VaultCore stays free of platform APIs; the app target
/// implements this with FileManager attributes. Called after every file write.
public protocol FileProtector: Sendable {
    func protect(_ url: URL, as protection: FileProtectionClass) throws
}

/// For tests and macOS, where Data Protection classes do not apply.
public struct NoFileProtection: FileProtector {
    public init() {}
    public func protect(_ url: URL, as protection: FileProtectionClass) throws {}
}
