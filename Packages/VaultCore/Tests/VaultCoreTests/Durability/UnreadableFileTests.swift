//
//  UnreadableFileTests.swift
//  VaultCoreTests
//
//  Created by Inez Amanda on 13/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import Testing

@testable import VaultCore

/// A file that is there but can't be read, like one iOS keeps locked while the phone is
/// locked, must never be taken for a missing or damaged file. Permissions stand in for
/// Data Protection, which a Mac test can't switch on.
@Suite("Files that can't be read right now")
struct UnreadableFileTests {
    func setReadable(_ readable: Bool, _ url: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: readable ? 0o600 : 0], ofItemAtPath: url.path)
    }

    /// A KTP saved, then edited, so index.prev.enc holds the older version.
    func makeEditedKTP() async throws -> (TestVault, DocumentID) {
        let vault = try TestVault()
        let store = vault.makeStore()
        try await store.open()
        let id = try await store.createDocument(
            type: .ktp, expiry: nil, pinned: false, fields: Synthetic.ktpFields, pages: [Synthetic.page("front")])
        try await store.editDocument(id, type: .ktp, label: nil, expiry: nil, pinned: true, fields: Synthetic.ktpFields)
        return (vault, id)
    }

    @Test func unreadableIndexStopsOpenAndChangesNothing() async throws {
        let (vault, id) = try await makeEditedKTP()
        let before = try TestVault.files(in: vault.base)
        try setReadable(false, vault.indexURL)
        // Before the fix, open fell back to index.prev.enc and lost the edit.
        await #expect(throws: VaultError.fileUnavailable) { try await vault.makeStore().open() }

        try setReadable(true, vault.indexURL)
        #expect(try TestVault.files(in: vault.base) == before)
        let store = vault.makeStore()
        let report = try await store.open()
        #expect(report.indexSource == .current)
        #expect(try await store.document(id).pinned)
    }

    @Test func unreadableHeaderStopsOpen() async throws {
        let (vault, _) = try await makeEditedKTP()
        try setReadable(false, vault.headerURL)
        await #expect(throws: VaultError.fileUnavailable) { try await vault.makeStore().open() }
    }

    @Test func unreadablePageDuringRecoveryStopsOpenAndChangesNothing() async throws {
        let (vault, _) = try await makeEditedKTP()
        try FileManager.default.removeItem(at: vault.indexURL)
        try FileManager.default.removeItem(at: vault.previousIndexURL)
        let page = try #require(try vault.pageFiles().first)
        let before = try TestVault.files(in: vault.base)
        try setReadable(false, page)
        await #expect(throws: VaultError.fileUnavailable) { try await vault.makeStore().open() }

        try setReadable(true, page)
        #expect(try TestVault.files(in: vault.base) == before)
    }

    @Test func unreadablePageIsUnavailable() async throws {
        let (vault, id) = try await makeEditedKTP()
        let store = vault.makeStore()
        try await store.open()
        let pageID = try await store.document(id).pageIDs[0]
        try setReadable(false, vault.pageURL(pageID))
        await #expect(throws: VaultError.fileUnavailable) { try await store.page(pageID, of: id) }
    }

    @Test func unreadableLiveHeaderKeepsTheVaultInUseSafe() async throws {
        // A copy of the live vault in Quarantine/. If the live vault.json can't be read,
        // deleting the copy must not go ahead, because it would delete the live key.
        let (vault, _) = try await makeEditedKTP()
        let liveID = try vault.header().vaultID
        let copy = vault.quarantineURL.appending(path: "20261013-090000", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: vault.quarantineURL, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: vault.root, to: copy)
        let store = vault.makeStore()
        let entry = try #require(try await store.quarantinedVaults(in: vault.quarantineURL).vaults.first)
        try setReadable(false, vault.headerURL)

        await #expect(throws: VaultError.fileUnavailable) { try await store.deleteQuarantinedVault(entry) }
        #expect(await vault.keyStore.key(for: liveID) != nil)
        #expect(FileManager.default.fileExists(atPath: copy.path))
    }

    /// The same with the whole vault folder unreadable: vault.json can't even be looked for.
    @Test func anUnreadableLiveFolderKeepsTheVaultInUseSafe() async throws {
        let (vault, _) = try await makeEditedKTP()
        let liveID = try vault.header().vaultID
        let copy = vault.quarantineURL.appending(path: "20261013-090000", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: vault.quarantineURL, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: vault.root, to: copy)
        let store = vault.makeStore()
        let entry = try #require(try await store.quarantinedVaults(in: vault.quarantineURL).vaults.first)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: vault.root.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: vault.root.path) }

        await #expect(throws: VaultError.fileUnavailable) { try await store.deleteQuarantinedVault(entry) }
        #expect(await vault.keyStore.key(for: liveID) != nil)
        #expect(FileManager.default.fileExists(atPath: copy.path))
    }

    /// A folder above the vault that can't be read hides the vault, so "nothing to quarantine" would
    /// send the app on to create a new one.
    @Test func quarantiningAnUnreadableVaultFolderThrows() async throws {
        let (vault, _) = try await makeEditedKTP()
        let before = try TestVault.files(in: vault.root)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: vault.base.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: vault.base.path) }

        await #expect(throws: VaultError.fileUnavailable) {
            try await vault.makeStore().quarantineVault(to: vault.quarantineURL)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: vault.base.path)
        #expect(try TestVault.files(in: vault.root) == before)
    }

    @Test func anUnreadableQuarantineFolderThrows() async throws {
        let (vault, _) = try await makeEditedKTP()
        let store = vault.makeStore()
        try await store.quarantineVault(to: vault.quarantineURL)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: vault.base.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: vault.base.path) }

        await #expect(throws: VaultError.fileUnavailable) { try await store.quarantinedVaults(in: vault.quarantineURL) }
    }

    @Test func unreadableOrphanStopsOpen() async throws {
        // An unreferenced page file that can't be read might still be someone's data.
        let (vault, _) = try await makeEditedKTP()
        let stray = vault.pageURL(PageID())
        try Data("synthetic".utf8).write(to: stray)
        try setReadable(false, stray)
        vault.clock.advance(by: 3600)
        await #expect(throws: VaultError.fileUnavailable) { try await vault.makeStore().open() }
        try setReadable(true, stray)
        #expect(FileManager.default.fileExists(atPath: stray.path))
    }
}
