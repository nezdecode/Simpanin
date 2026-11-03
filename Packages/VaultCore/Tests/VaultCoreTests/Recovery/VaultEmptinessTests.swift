//
//  VaultEmptinessTests.swift
//  VaultCoreTests
//
//  Created by Inez Amanda on 3/11/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import Testing

@testable import VaultCore

/// `isEmpty(in:)` decides whether the app may show its welcome screen: only when nothing in the
/// folder could be part of a vault. Anything that could be goes to `open()` and its recovery screens.
@Suite("Vault emptiness")
struct VaultEmptinessTests {
    private func makeFolders(_ vault: TestVault) throws {
        try FileManager.default.createDirectory(at: vault.pagesDirectory, withIntermediateDirectories: true)
    }

    private func touch(_ url: URL) throws {
        try Data("leftover".utf8).write(to: url)
    }

    private var pageFileName: String { "\(PageID().string).enc" }

    @Test func nothingAtAllIsEmpty() throws {
        let vault = try TestVault()
        #expect(try VaultStore.isEmpty(in: vault.root))
    }

    @Test func emptyFoldersLeftByAnInterruptedCreateAreEmpty() throws {
        let vault = try TestVault()
        try makeFolders(vault)
        #expect(try VaultStore.isEmpty(in: vault.root))
    }

    /// A temp file was never part of a save, and creating the vault writes over the header's.
    @Test func aLeftoverHeaderTempFileIsEmpty() throws {
        let vault = try TestVault()
        try makeFolders(vault)
        try touch(vault.root.appending(path: ".vault.json.tmp"))
        #expect(try VaultStore.isEmpty(in: vault.root))
    }

    @Test func leftoverIndexAndPageTempFilesAreEmpty() throws {
        let vault = try TestVault()
        try makeFolders(vault)
        try touch(vault.root.appending(path: ".index.enc.tmp"))
        try touch(vault.pagesDirectory.appending(path: ".\(pageFileName).tmp"))
        #expect(try VaultStore.isEmpty(in: vault.root))
    }

    @Test func aHeaderIsNotEmpty() async throws {
        let vault = try TestVault()
        try await vault.makeStore().open()
        #expect(try !VaultStore.isEmpty(in: vault.root))
    }

    @Test(arguments: ["index.enc", "index.prev.enc"])
    func anIndexWithoutAHeaderIsNotEmpty(_ name: String) throws {
        let vault = try TestVault()
        try makeFolders(vault)
        try touch(vault.root.appending(path: name))
        #expect(try !VaultStore.isEmpty(in: vault.root))
    }

    @Test func aPageFileWithoutAHeaderIsNotEmpty() throws {
        let vault = try TestVault()
        try makeFolders(vault)
        try touch(vault.pagesDirectory.appending(path: pageFileName))
        #expect(try !VaultStore.isEmpty(in: vault.root))
    }

    /// An unreadable folder may hold documents, so it must never be taken for an empty one.
    @Test func anUnreadablePagesFolderThrows() throws {
        let vault = try TestVault()
        try makeFolders(vault)
        let fileManager = FileManager.default
        try fileManager.setAttributes([.posixPermissions: 0o000], ofItemAtPath: vault.pagesDirectory.path)
        defer { try? fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: vault.pagesDirectory.path) }
        #expect(throws: (any Error).self) { try VaultStore.isEmpty(in: vault.root) }
    }

    /// Its files can't even be looked for, so it may hold a vault: never taken for an empty one.
    @Test func anUnreadableVaultFolderThrows() throws {
        let vault = try TestVault()
        try makeFolders(vault)
        try touch(vault.root.appending(path: "vault.json"))
        let fileManager = FileManager.default
        try fileManager.setAttributes([.posixPermissions: 0o000], ofItemAtPath: vault.root.path)
        defer { try? fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: vault.root.path) }
        #expect(throws: VaultError.fileUnavailable) { try VaultStore.isEmpty(in: vault.root) }
    }

    @Test func openingAnEmptyFolderWithAHeaderTempFileCreatesAVault() async throws {
        let vault = try TestVault()
        try makeFolders(vault)
        try touch(vault.root.appending(path: ".vault.json.tmp"))
        let report = try await vault.makeStore().open()
        #expect(report.createdVault)
        #expect(!FileManager.default.fileExists(atPath: vault.root.appending(path: ".vault.json.tmp").path))
        #expect(try !VaultStore.isEmpty(in: vault.root))
    }

    @Test func creatingTheVaultRemovesLeftoverIndexAndPageTempFiles() async throws {
        let vault = try TestVault()
        try makeFolders(vault)
        let indexTemp = vault.root.appending(path: ".index.enc.tmp")
        let pageTemp = vault.pagesDirectory.appending(path: ".\(pageFileName).tmp")
        try touch(indexTemp)
        try touch(pageTemp)
        let report = try await vault.makeStore().open()
        #expect(report.createdVault)
        #expect(!FileManager.default.fileExists(atPath: indexTemp.path))
        #expect(!FileManager.default.fileExists(atPath: pageTemp.path))
    }
}
