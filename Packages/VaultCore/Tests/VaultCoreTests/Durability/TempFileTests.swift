//
//  TempFileTests.swift
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

/// A leftover temp file can be a second name for its target: a new header is linked into place,
/// and if removing the temp name fails, both names share one file. Writing through it would
/// change the target before the rename, so `write()` never does.
@Suite("Leftover temp files")
struct TempFileTests {
    func makeStore(_ vault: TestVault, _ protector: any FileProtector) -> VaultStore {
        VaultStore(
            rootDirectory: vault.root, projectionURL: vault.projectionURL, keyStore: vault.keyStore,
            clock: vault.clock, fileProtector: protector, crashHook: nil)
    }

    @Test func aLeftoverHardLinkedTempNeverTruncatesTheHeader() async throws {
        let vault = try TestVault()
        try await vault.makeStore().open()
        let header = try Data(contentsOf: vault.headerURL)
        let temp = VaultStore.tempURL(for: vault.headerURL)
        #expect(link(vault.headerURL.path, temp.path) == 0)
        let protector = FailingProtector(failingOn: "vault.json")
        protector.arm(true)

        // The write fails before its rename, so vault.json must still be the old header.
        await #expect(throws: CocoaError.self) {
            try await makeStore(vault, protector).write(
                Data("synthetic".utf8), to: vault.headerURL, protection: .complete)
        }
        #expect(try Data(contentsOf: vault.headerURL) == header)
    }

    @Test func aTempThatCantBeRemovedStopsTheWrite() async throws {
        let vault = try TestVault()
        try await vault.makeStore().open()
        let header = try Data(contentsOf: vault.headerURL)
        // A folder whose content can't be deleted stands in for a temp name that won't go.
        let temp = VaultStore.tempURL(for: vault.headerURL)
        let inner = temp.appending(path: "locked", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: true)
        try Data("synthetic".utf8).write(to: inner.appending(path: "file"))
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: inner.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: inner.path) }

        await #expect(throws: (any Error).self) {
            try await vault.makeStore().write(Data("synthetic".utf8), to: vault.headerURL, protection: .complete)
        }
        #expect(try Data(contentsOf: vault.headerURL) == header)
    }
}
