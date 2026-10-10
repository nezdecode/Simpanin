//
//  PurgeTests.swift
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

/// After a purge, no file in the vault holds the purged sealed key.
@Suite("Purge")
struct PurgeTests {
    struct Setup {
        let vault: TestVault
        let store: VaultStore
        let purged: DocumentID
        let kept: DocumentID
        let purgedPages: [PageID]
        let sealedKey: Data
        let rawKey: Data
        let deletedAt: Date
    }

    func makeSetup() async throws -> Setup {
        let vault = try TestVault(clock: TestClock(Date(timeIntervalSince1970: 1_790_000_000)))
        let store = vault.makeStore()
        try await store.open()
        let purged = try await store.createDocument(
            type: .ktp, expiry: nil, pinned: false, fields: Synthetic.ktpFields,
            pages: [Synthetic.page("p1"), Synthetic.page("p2")])
        let kept = try await store.createDocument(
            type: .sim, expiry: Synthetic.simExpiry, pinned: false,
            fields: Synthetic.simFields, pages: [Synthetic.page("k1")])
        try await store.editDocument(purged, type: .ktp, expiry: nil, pinned: true, fields: Synthetic.ktpFields)
        try await store.delete(purged)

        let entry = try #require(try await vault.readIndex(at: vault.indexURL).documents.first { $0.id == purged })
        let header = try vault.header()
        let vaultKey = try #require(await vault.keyStore.key(for: header.vaultId))
        let wrapKey = VaultCrypto.wrapKey(from: vaultKey, vaultID: header.vaultId)
        let rawKey = bytes(try VaultCrypto.openDocumentKey(entry.sealedKey, with: wrapKey, documentID: purged))
        return Setup(
            vault: vault, store: store, purged: purged, kept: kept, purgedPages: entry.pageIds,
            sealedKey: entry.sealedKey, rawKey: rawKey, deletedAt: try #require(entry.deletedAt))
    }

    func expectNoTrace(_ setup: Setup, _ store: VaultStore) async throws {
        #expect(try await store.documents().map(\.id) == [setup.kept])
        #expect(try await store.recentlyDeleted().isEmpty)
        await #expect(throws: VaultError.documentNotFound) { try await store.fields(of: setup.purged) }
        for page in setup.purgedPages {
            #expect(!FileManager.default.fileExists(atPath: setup.vault.pageURL(page).path))
        }
        // Both index files open and neither holds the entry or its sealed key.
        for url in [setup.vault.indexURL, setup.vault.previousIndexURL] {
            let index = try await setup.vault.readIndex(at: url)
            #expect(!index.documents.contains { $0.id == setup.purged }, "\(url.lastPathComponent)")
            #expect(!index.documents.contains { $0.sealedKey == setup.sealedKey }, "\(url.lastPathComponent)")
        }
        // Decode the headers rather than byte-scan: JSON escapes "/" in the base64 key, so a
        // byte search would miss it.
        for file in try setup.vault.pageFiles() {
            let header = try PageFile(decoding: Data(contentsOf: file)).header
            #expect(header.sealedKey != setup.sealedKey, "sealed key in \(file.lastPathComponent)")
            #expect(header.docId != setup.purged, "page of the purged document: \(file.lastPathComponent)")
        }
        // The document id appears as plain text in page headers, so a byte scan does work for it.
        for file in try setup.vault.allFiles() {
            let data = try Data(contentsOf: file)
            #expect(!data.contains(bytes: Data(setup.purged.string.utf8)), "doc id in \(file.lastPathComponent)")
        }
        // The other document is untouched.
        #expect(try await store.fields(of: setup.kept) == Synthetic.simFields)
        #expect(try await store.pages(of: setup.kept).map(\.data) == [Synthetic.page("k1")])
    }

    @Test func notPurgedBeforeThirtyDays() async throws {
        let setup = try await makeSetup()
        setup.vault.clock.set(setup.deletedAt + 30 * 86_400 - 1)
        let store = setup.vault.makeStore()
        #expect(try await store.open().purgedDocuments == 0)
        #expect(try await store.recentlyDeleted().map(\.id) == [setup.purged])
        #expect(try await store.fields(of: setup.purged) == Synthetic.ktpFields)
    }

    @Test func purgedOnUnlockAfterThirtyDays() async throws {
        let setup = try await makeSetup()
        setup.vault.clock.set(setup.deletedAt + 30 * 86_400)
        let store = setup.vault.makeStore()
        #expect(try await store.open().purgedDocuments == 1)
        try await expectNoTrace(setup, store)
    }

    @Test func purgeExpiredWhileOpen() async throws {
        let setup = try await makeSetup()
        setup.vault.clock.set(setup.deletedAt + 31 * 86_400)
        #expect(try await setup.store.purgeExpired() == 1)
        try await expectNoTrace(setup, setup.store)
        #expect(try await setup.store.purgeExpired() == 0)
    }

    @Test func deletePermanentlyNow() async throws {
        let setup = try await makeSetup()
        try await setup.store.deletePermanently(setup.purged)
        try await expectNoTrace(setup, setup.store)
    }

    @Test func purgedDocumentDoesNotComeBackThroughRecovery() async throws {
        let setup = try await makeSetup()
        try await setup.store.deletePermanently(setup.purged)
        try Data("x".utf8).write(to: setup.vault.indexURL)
        try Data("x".utf8).write(to: setup.vault.previousIndexURL)

        let store = setup.vault.makeStore()
        #expect(try await store.open().indexSource == .recovered)
        #expect(try await store.documents().map(\.id) == [setup.kept])
        #expect(try await store.recentlyDeleted().isEmpty)
        #expect(try await store.pages(of: setup.kept).map(\.data) == [Synthetic.page("k1")])
    }

    @Test func purgeWritesTheIndexTwice() async throws {
        let setup = try await makeSetup()
        let before = try await setup.vault.readIndex(at: setup.vault.indexURL).generation
        try await setup.store.deletePermanently(setup.purged)
        #expect(try await setup.vault.readIndex(at: setup.vault.indexURL).generation == before + 2)
        #expect(try await setup.vault.readIndex(at: setup.vault.previousIndexURL).generation == before + 1)
    }
}
