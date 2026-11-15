//
//  UndecodableIndexTests.swift
//  VaultCoreTests
//
//  Created by Inez Amanda on 15/11/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import Testing

@testable import VaultCore

/// An index that opens with the vault's key was written correctly, so failing to decode it
/// means this build can't read it. An open never falls back over it, rebuilds or rewrites it.
@Suite("An index that opens but doesn't decode")
struct UndecodableIndexTests {
    /// The probe decodes but the full index doesn't.
    static let wrongShape = Data(#"{"schemaVersion":2,"generation":"one","documents":[]}"#.utf8)
    /// Not even the schema version can be read.
    static let noVersion = Data("not an index".utf8)

    func makeVault() async throws -> (TestVault, DocumentID) {
        let vault = try TestVault()
        let store = vault.makeStore()
        try await store.open()
        let id = try await store.createDocument(
            type: .ktp, expiry: nil, pinned: false, fields: Synthetic.ktpFields,
            pages: [Synthetic.page("front")])
        try await store.editDocument(id, type: .ktp, label: nil, expiry: nil, pinned: true, fields: Synthetic.ktpFields)
        return (vault, id)
    }

    /// Seals `plain` with the vault's real index key, so the seal opens.
    func seal(_ plain: Data, to url: URL, in vault: TestVault) async throws {
        let header = try vault.header()
        let key = try #require(await vault.keyStore.key(for: header.vaultID))
        let indexKey = VaultCrypto.indexKey(from: key, vaultID: header.vaultID)
        try VaultCrypto.seal(plain, with: indexKey, as: .index(header.vaultID)).write(to: url)
    }

    func expectOpenStopsAndChangesNothing(_ vault: TestVault) async throws {
        let before = try TestVault.files(in: vault.base)
        await #expect(throws: VaultError.indexNotDecodable) { try await vault.makeStore().open() }
        #expect(try TestVault.files(in: vault.base) == before)
    }

    @Test func undecodableIndexStopsOpenAndChangesNothing() async throws {
        let (vault, _) = try await makeVault()
        try await seal(Self.wrongShape, to: vault.indexURL, in: vault)
        // index.prev.enc still reads, but falling back would overwrite index.enc.
        try await expectOpenStopsAndChangesNothing(vault)
    }

    @Test func undecodableIndexWithNoPreviousIndexStopsOpen() async throws {
        let (vault, _) = try await makeVault()
        try await seal(Self.wrongShape, to: vault.indexURL, in: vault)
        try FileManager.default.removeItem(at: vault.previousIndexURL)
        try await expectOpenStopsAndChangesNothing(vault)
    }

    @Test func bothIndexFilesUndecodableStopOpenAndChangeNothing() async throws {
        let (vault, _) = try await makeVault()
        try await seal(Self.wrongShape, to: vault.indexURL, in: vault)
        try await seal(Self.wrongShape, to: vault.previousIndexURL, in: vault)
        // Today's code rebuilt the vault from its pages here and wrote over both files.
        try await expectOpenStopsAndChangesNothing(vault)
    }

    @Test func undecodablePreviousIndexOpensFromTheCurrentIndex() async throws {
        let (vault, id) = try await makeVault()
        try await seal(Self.wrongShape, to: vault.previousIndexURL, in: vault)

        let store = vault.makeStore()
        let report = try await store.open()
        #expect(report.indexSource == .current)
        #expect(!report.newestChangeMayBeLost)
        #expect(!report.recoveredFromPages)
        #expect(try await store.document(id).pinned)
        #expect(try await store.fields(of: id) == Synthetic.ktpFields)

        // The next save moves the readable index.enc over the old file.
        try await store.editDocument(
            id, type: .ktp, label: nil, expiry: nil, pinned: false, fields: Synthetic.ktpFields)
        #expect(try await vault.readIndex(at: vault.previousIndexURL).documents.first?.pinned == true)
    }

    enum CurrentIndex: CaseIterable { case missing, damaged }

    @Test(arguments: CurrentIndex.allCases)
    func undecodablePreviousIndexWithoutAReadableIndexStopsOpen(_ current: CurrentIndex) async throws {
        let (vault, _) = try await makeVault()
        try await seal(Self.wrongShape, to: vault.previousIndexURL, in: vault)
        switch current {
        case .missing:
            try FileManager.default.removeItem(at: vault.indexURL)
        case .damaged:
            var data = try Data(contentsOf: vault.indexURL)
            data[data.count / 2] ^= 0xFF
            try data.write(to: vault.indexURL)
        }
        try await expectOpenStopsAndChangesNothing(vault)
    }

    @Test func anIndexWithoutAReadableVersionStopsOpen() async throws {
        let (vault, _) = try await makeVault()
        try await seal(Self.noVersion, to: vault.indexURL, in: vault)
        try await expectOpenStopsAndChangesNothing(vault)
    }
}
