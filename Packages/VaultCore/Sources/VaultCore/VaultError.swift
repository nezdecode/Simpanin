/// Errors from VaultCore. Cases carry no ids, field values or file contents, so they
/// are safe to log.
public enum VaultError: Error, Equatable, Sendable {
    /// Sealed data failed to open: wrong key, wrong associated data, or tampered bytes.
    case authenticationFailed
    /// A file could not be decoded (bad JSON, bad header, wrong key length).
    case corruptFile
    /// A file has a format or schema version newer than this build understands.
    case unsupportedVersion
    /// The key store reports the vault key exists but cannot be read now (locked,
    /// passcode removed, user cancelled). The vault must not be recreated.
    /// `status` is the Keychain status code when the key store gave one (for example
    /// -25293 after the passcode was turned off), nil for any other error.
    case vaultKeyUnavailable(status: Int32?)
    /// vault.json exists but the key store has no vault key for it. Never answered by
    /// creating a new key, because that would orphan every document.
    case vaultKeyMissing
    /// Vault files exist but vault.json does not; refuse to create a new vault over them.
    case vaultHeaderMissing
    /// Neither index file nor any page file could be opened with this vault key.
    case vaultUnreadable
    /// The vault is locked; call `open()` first.
    case locked
    case documentNotFound
    case pageNotFound
    /// The document is in Recently deleted; restore it before editing or changing pages.
    case documentDeleted
    /// A quarantine folder's vault.json cannot be read, or names a different vault than
    /// expected. The folder is left untouched.
    case quarantineUnreadable
    /// The quarantine entry names the vault that is in use. Nothing is deleted.
    case quarantineInUse
    /// Flushing the new index to disk failed, so step 3 deleted nothing.
    case flushFailed
}
