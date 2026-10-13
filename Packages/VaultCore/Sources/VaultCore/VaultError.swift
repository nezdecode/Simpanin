//
//  VaultError.swift
//  VaultCore
//
//  Created by Inez Amanda on 4/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

/// Errors from VaultCore. Cases carry no ids, field values or file contents, so they
/// are safe to log. File system errors, like a full disk, are passed through as they are.
public enum VaultError: Error, Equatable, Sendable {
    /// Sealed data didn't open. The key or associated data was wrong, or the bytes were changed.
    case authenticationFailed
    /// A file couldn't be decoded, for example bad JSON, a bad header or a key of the wrong length.
    case corruptFile
    /// A file is there but can't be read right now, for example while the phone is locked.
    /// Nothing was changed, so try again later.
    case fileUnavailable
    /// A file has a format or schema version newer than this build understands.
    case unsupportedVersion
    /// The vault key exists but can't be read right now, so don't recreate the vault. `status`
    /// is the Keychain status code, if there was one.
    case vaultKeyUnavailable(status: Int32?)
    /// vault.json is there but its key isn't. Don't make a new key, or every document is lost.
    case vaultKeyMissing
    /// There are vault files but no vault.json, so don't create a new vault on top of them.
    case vaultHeaderMissing
    /// Neither index file nor any page file could be opened with this vault key.
    case vaultUnreadable
    /// The vault is locked. Call `open()` first.
    case locked
    case documentNotFound
    /// The id isn't in the document, or the page's file is gone.
    case pageNotFound
    /// The document is in Recently deleted. Restore it before editing it or its pages.
    case documentDeleted
    /// A quarantine folder's vault.json is unreadable or names another vault.
    case quarantineUnreadable
    /// The quarantine entry names the vault that is in use. Nothing is deleted.
    case quarantineInUse
    /// A flush before deleting files failed, so nothing was deleted.
    case flushFailed
}
