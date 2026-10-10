//
//  VersionTests.swift
//  VaultCoreTests
//
//  Created by Inez Amanda on 4/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Crypto
import Foundation
import Testing

@testable import VaultCore

/// A file from a newer app version stops this one with `unsupportedVersion`. Treating it as
/// corrupt would fall back or recover, and overwrite it.
@Suite("Newer format versions")
struct VersionTests {
    func makeVault() async throws -> (TestVault, DocumentID) {
        let vault = try TestVault()
        let store = vault.makeStore()
        try await store.open()
        let id = try await store.createDocument(
            type: .ktp, expiry: nil, pinned: false, fields: Synthetic.ktpFields,
            pages: [Synthetic.page("front")])
        try await store.editDocument(id, type: .ktp, expiry: nil, pinned: true, fields: Synthetic.ktpFields)
        return (vault, id)
    }

    /// Rewrites a JSON object's top-level key in place.
    func setting(_ key: String, to value: Int, in json: Data) throws -> Data {
        var object = try #require(JSONSerialization.jsonObject(with: json) as? [String: Any])
        object[key] = value
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    @Test func vaultFileFromANewerVersionStopsOpen() async throws {
        let (vault, _) = try await makeVault()
        try setting("formatVersion", to: 2, in: Data(contentsOf: vault.headerURL)).write(to: vault.headerURL)
        let before = try TestVault.files(in: vault.base)

        await #expect(throws: VaultError.unsupportedVersion) { try await vault.makeStore().open() }
        #expect(try TestVault.files(in: vault.base) == before)
        #expect(await vault.keyStore.createCount == 1)
    }

    @Test func indexFromANewerVersionStopsOpen() async throws {
        let (vault, _) = try await makeVault()
        let header = try vault.header()
        let key = try #require(await vault.keyStore.key(for: header.vaultId))
        let indexKey = VaultCrypto.indexKey(from: key, vaultID: header.vaultId)
        let plain = try VaultCrypto.open(Data(contentsOf: vault.indexURL), with: indexKey, as: .index(header.vaultId))
        let newer = try setting("schemaVersion", to: 2, in: plain)
        try VaultCrypto.seal(newer, with: indexKey, as: .index(header.vaultId)).write(to: vault.indexURL)
        let before = try TestVault.files(in: vault.base)

        // index.prev.enc is still a readable v1 index; the store must not fall back to it.
        await #expect(throws: VaultError.unsupportedVersion) { try await vault.makeStore().open() }
        #expect(try TestVault.files(in: vault.base) == before)
    }

    func rewritePageHeaderVersion(at url: URL) throws {
        var file = try PageFile(decoding: Data(contentsOf: url))
        file.header.formatVersion = 2
        try file.encoded().write(to: url)
    }

    @Test func pageFromANewerVersionCannotBeRead() async throws {
        let (vault, id) = try await makeVault()
        let store = vault.makeStore()
        try await store.open()
        let pageID = try await store.document(id).pageIDs[0]
        try rewritePageHeaderVersion(at: vault.pageURL(pageID))
        let before = try TestVault.files(in: vault.base)

        await #expect(throws: VaultError.unsupportedVersion) { try await store.page(pageID, of: id) }
        // Reopening, an hour later, keeps the file: it is referenced, and a newer page is
        // never deleted.
        vault.clock.advance(by: 3600)
        try await vault.makeStore().open()
        #expect(try TestVault.files(in: vault.base) == before)
    }

    @Test func unreferencedPageFromANewerVersionIsNeverDeleted() async throws {
        let (vault, _) = try await makeVault()
        // A page a newer version wrote but this vault's index does not reference.
        let store = vault.makeStore()
        try await store.open()
        let other = try await store.createDocument(
            type: .sim, expiry: nil, pinned: false, fields: Synthetic.simFields,
            pages: [Synthetic.page("sim")])
        let orphan = vault.pageURL(try await store.document(other).pageIDs[0])
        let entryless = try await vault.readIndex(at: vault.previousIndexURL)  // before the SIM existed
        let header = try vault.header()
        let key = try #require(await vault.keyStore.key(for: header.vaultId))
        let indexKey = VaultCrypto.indexKey(from: key, vaultID: header.vaultId)
        var rolledBack = entryless
        rolledBack.generation += 10
        try VaultCrypto.seal(VaultJSON.encoder.encode(rolledBack), with: indexKey, as: .index(header.vaultId))
            .write(to: vault.indexURL)
        try rewritePageHeaderVersion(at: orphan)

        vault.clock.advance(by: 3600)
        let report = try await vault.makeStore().open()
        #expect(report.removedOrphanPages == 0)
        #expect(report.unreadablePages == 1)
        #expect(FileManager.default.fileExists(atPath: orphan.path))
    }
}
