//
//  NoVaultGuardTests.swift
//  VaultCoreTests
//
//  Created by Inez Amanda on 4/11/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import Testing

@testable import VaultCore

/// `open()` creates a vault only when it can see there's none. A folder it can't look in may hold
/// documents, so it stops with `fileUnavailable` before any key is made. Permissions stand in for
/// Data Protection, which a Mac test can't switch on.
@Suite("Creating a vault only when there's none")
struct NoVaultGuardTests {
    func setReadable(_ readable: Bool, _ folder: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: readable ? 0o755 : 0], ofItemAtPath: folder.path)
    }

    /// A vault with one KTP, saved long enough ago that its pages are past the orphan age.
    func makeVault() async throws -> (vault: TestVault, id: DocumentID, vaultID: VaultID) {
        let vault = try TestVault()
        let store = vault.makeStore()
        try await store.open()
        let id = try await store.createDocument(
            type: .ktp, expiry: nil, pinned: false, fields: Synthetic.ktpFields, pages: [Synthetic.page("front")])
        vault.clock.advance(by: 3600)
        return (vault, id, try vault.header().vaultID)
    }

    @Test func anUnreadableVaultFolderWithAHeaderThrowsAndCreatesNoKey() async throws {
        let (vault, _, _) = try await makeVault()
        let before = try TestVault.files(in: vault.base)
        let creates = await vault.keyStore.createCount
        try setReadable(false, vault.root)
        defer { try? setReadable(true, vault.root) }

        await #expect(throws: VaultError.fileUnavailable) { try await vault.makeStore().open() }
        #expect(await vault.keyStore.createCount == creates)
        try setReadable(true, vault.root)
        #expect(try TestVault.files(in: vault.base) == before)
    }

    /// The 4 Oct rule (vault.json there, key missing: never make a key) must hold even when
    /// vault.json can't be seen.
    @Test func anUnreadableVaultFolderWithAHeaderAndNoKeyNeverCreatesOne() async throws {
        let (vault, _, vaultID) = try await makeVault()
        await vault.keyStore.setKey(nil, for: vaultID)
        let creates = await vault.keyStore.createCount
        try setReadable(false, vault.root)
        defer { try? setReadable(true, vault.root) }

        await #expect(throws: VaultError.fileUnavailable) { try await vault.makeStore().open() }
        #expect(await vault.keyStore.createCount == creates)
        try setReadable(true, vault.root)
        await #expect(throws: VaultError.vaultKeyMissing) { try await vault.makeStore().open() }
    }

    @Test func anUnreadableParentFolderThrowsAndCreatesNoKey() async throws {
        let (vault, _, _) = try await makeVault()
        let creates = await vault.keyStore.createCount
        try setReadable(false, vault.base)
        defer { try? setReadable(true, vault.base) }

        await #expect(throws: VaultError.fileUnavailable) { try await vault.makeStore().open() }
        #expect(await vault.keyStore.createCount == creates)
    }

    @Test func anUnreadablePagesFolderWithoutAHeaderThrowsAndCreatesNoKey() async throws {
        let (vault, _, _) = try await makeVault()
        // Only the pages are left, so they alone decide.
        for url in [vault.headerURL, vault.indexURL, vault.previousIndexURL] {
            try FileManager.default.removeItem(at: url)
        }
        let creates = await vault.keyStore.createCount
        try setReadable(false, vault.pagesDirectory)
        defer { try? setReadable(true, vault.pagesDirectory) }

        await #expect(throws: VaultError.fileUnavailable) { try await vault.makeStore().open() }
        #expect(await vault.keyStore.createCount == creates)
        #expect(!FileManager.default.fileExists(atPath: vault.headerURL.path))
    }

    @Test func aFolderReadableAgainOpensTheSameVault() async throws {
        let (vault, id, vaultID) = try await makeVault()
        let creates = await vault.keyStore.createCount
        try setReadable(false, vault.root)
        defer { try? setReadable(true, vault.root) }
        await #expect(throws: VaultError.fileUnavailable) { try await vault.makeStore().open() }

        try setReadable(true, vault.root)
        let store = vault.makeStore()
        let report = try await store.open()
        #expect(!report.createdVault)
        #expect(try vault.header().vaultID == vaultID)
        #expect(try await store.document(id).type == .ktp)
        #expect(await vault.keyStore.createCount == creates)
    }

    @Test func aVaultFolderThatIsAFileThrows() async throws {
        let vault = try TestVault()
        try Data("synthetic".utf8).write(to: vault.root)

        await #expect(throws: VaultError.fileUnavailable) { try await vault.makeStore().open() }
        #expect(await vault.keyStore.createCount == 0)
    }

    /// The key comes first, so a failed header write leaves an unused key and no header, never a
    /// header without its key. The retry makes a vault as usual.
    @Test func aHeaderWriteThatFailsAfterTheKeyLeavesNoHeader() async throws {
        let vault = try TestVault()
        let protector = FailingProtector(failingOn: "vault.json")
        protector.arm(true)
        let failing = VaultStore(
            rootDirectory: vault.root, projectionURL: vault.projectionURL, keyStore: vault.keyStore,
            clock: vault.clock, fileProtector: protector, crashHook: nil)

        await #expect(throws: CocoaError.self) { try await failing.open() }
        #expect(await vault.keyStore.createCount == 1)
        #expect(!FileManager.default.fileExists(atPath: vault.headerURL.path))
        #expect(!FileManager.default.fileExists(atPath: VaultStore.tempURL(for: vault.headerURL).path))

        protector.arm(false)
        #expect(try await failing.open().createdVault)
        #expect(await vault.keyStore.createCount == 2)
    }

    /// A vault that turns up while the key is being made, like a folder readable again, is moved
    /// back into place by the key store's create hook. The new header must not replace its own.
    func makeVaultThatReturnsDuringCreate() async throws -> (vault: TestVault, id: DocumentID, files: [String: Data]) {
        let (vault, id, _) = try await makeVault()
        let files = try TestVault.files(in: vault.root)
        let away = vault.base.appending(path: "Away", directoryHint: .isDirectory)
        try FileManager.default.moveItem(at: vault.root, to: away)
        let root = vault.root
        await vault.keyStore.setCreateHook { try FileManager.default.moveItem(at: away, to: root) }
        return (vault, id, files)
    }

    @Test func creatingNeverReplacesAnExistingHeader() async throws {
        let (vault, _, files) = try await makeVaultThatReturnsDuringCreate()

        await #expect(throws: VaultError.fileUnavailable) { try await vault.makeStore().open() }
        #expect(try TestVault.files(in: vault.root) == files)
    }

    @Test func aHeaderWrittenDuringCreateOpensOnRetry() async throws {
        let (vault, id, _) = try await makeVaultThatReturnsDuringCreate()
        let store = vault.makeStore()
        await #expect(throws: VaultError.fileUnavailable) { try await store.open() }

        await vault.keyStore.setCreateHook(nil)
        let report = try await store.open()
        #expect(!report.createdVault)
        #expect(try await store.document(id).type == .ktp)
    }

    @Test func theNewHeaderKeepsItsProtectionClass() async throws {
        let vault = try TestVault()
        let protector = RecordingProtector()
        let store = VaultStore(
            rootDirectory: vault.root, projectionURL: vault.projectionURL, keyStore: vault.keyStore,
            clock: vault.clock, fileProtector: protector, crashHook: nil)
        try await store.open()
        let temp = VaultStore.tempURL(for: vault.headerURL).standardizedFileURL
        #expect(protector.calls.contains { $0.url.standardizedFileURL == temp && $0.protection == .complete })
        #expect(FileManager.default.fileExists(atPath: vault.headerURL.path))
        #expect(!FileManager.default.fileExists(atPath: temp.path))
    }

    @Test func aFullDiskWhileCreatingLeavesNoHeader() async throws {
        let vault = try TestVault()
        let protector = FailingProtector(failingOn: "vault.json", with: CocoaError(.fileWriteOutOfSpace))
        protector.arm(true)
        let store = VaultStore(
            rootDirectory: vault.root, projectionURL: vault.projectionURL, keyStore: vault.keyStore,
            clock: vault.clock, fileProtector: protector, crashHook: nil)

        await #expect(throws: VaultError.storageFull) { try await store.open() }
        #expect(!FileManager.default.fileExists(atPath: vault.headerURL.path))
        #expect(!FileManager.default.fileExists(atPath: VaultStore.tempURL(for: vault.headerURL).path))
    }

    /// Recovery from pages must never go on from a listing it couldn't read: it would write an
    /// index without those pages.
    @Test func anUnreadablePagesFolderDuringRecoveryWritesNothing() async throws {
        let (vault, _, _) = try await makeVault()
        try Data("damaged".utf8).write(to: vault.indexURL)
        try Data("damaged".utf8).write(to: vault.previousIndexURL)
        let before = try TestVault.files(in: vault.base)
        try setReadable(false, vault.pagesDirectory)
        defer { try? setReadable(true, vault.pagesDirectory) }

        await #expect(throws: VaultError.fileUnavailable) { try await vault.makeStore().open() }
        try setReadable(true, vault.pagesDirectory)
        #expect(try TestVault.files(in: vault.base) == before)
        let store = vault.makeStore()
        #expect(try await store.open().recoveredFromPages)
        #expect(try await store.documents().count == 1)
    }
}
