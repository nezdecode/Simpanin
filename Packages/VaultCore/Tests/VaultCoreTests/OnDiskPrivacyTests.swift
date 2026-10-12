//
//  OnDiskPrivacyTests.swift
//  VaultCoreTests
//
//  Created by Inez Amanda on 12/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import Testing

@testable import VaultCore

/// What someone with a copy of the vault files can learn without the key.
@Suite("What the files reveal")
struct OnDiskPrivacyTests {
    @Test func noPlaintextFieldsOrPagesOnDisk() async throws {
        let vault = try TestVault()
        let store = vault.makeStore()
        try await store.open()
        let page = Synthetic.page("ktp-front")
        let id = try await store.createDocument(
            type: .ktp, expiry: nil, pinned: false,
            fields: Synthetic.ktpFields, pages: [page])
        try await store.editDocument(id, type: .ktp, expiry: nil, pinned: false, fields: Synthetic.ktpFields)
        for file in try vault.allFiles() {
            let data = try Data(contentsOf: file)
            #expect(!data.contains(bytes: Data(Synthetic.nik.utf8)), "NIK in \(file.lastPathComponent)")
            #expect(!data.contains(bytes: Data(Synthetic.name.utf8)), "name in \(file.lastPathComponent)")
            #expect(!data.contains(bytes: page.prefix(64)), "page bytes in \(file.lastPathComponent)")
        }
    }

    @Test func noKeyIsWrittenToDisk() async throws {
        let vault = try TestVault()
        let store = vault.makeStore()
        try await store.open()
        let ktp = try await store.createDocument(
            type: .ktp, expiry: nil, pinned: false, fields: Synthetic.ktpFields, pages: [Synthetic.page("front")])
        let sim = try await store.createDocument(
            type: .sim, expiry: nil, pinned: false, fields: Synthetic.simFields, pages: [Synthetic.page("sim")])
        try await store.editDocument(ktp, type: .ktp, expiry: nil, pinned: true, fields: Synthetic.ktpFields)
        _ = try await store.addPage(Synthetic.page("back"), to: ktp)
        try await store.delete(sim)
        try await store.deletePermanently(sim)

        let header = try vault.header()
        let vaultKey = try #require(await vault.keyStore.key(for: header.vaultId))
        let wrapKey = VaultCrypto.wrapKey(from: vaultKey, vaultID: header.vaultId)
        let index = try await vault.readIndex(at: vault.indexURL)
        let entry = try #require(index.documents.first)
        let documentKey = try VaultCrypto.openDocumentKey(entry.sealedKey, with: wrapKey, documentID: ktp)
        let files = try vault.allFiles().map { try Data(contentsOf: $0) }

        // A key could be stored raw or as base64 in JSON, where "/" is escaped as "\/".
        func onDisk(_ bytes: Data) -> Bool {
            let base64 = bytes.base64EncodedString()
            let forms = [bytes, Data(base64.utf8), Data(base64.replacingOccurrences(of: "/", with: "\\/").utf8)]
            return files.contains { file in forms.contains { file.contains(bytes: $0) } }
        }
        // The search works: the sealed document key is in the plaintext page headers.
        #expect(onDisk(entry.sealedKey))
        #expect(!onDisk(bytes(vaultKey)), "vault key")
        #expect(!onDisk(bytes(VaultCrypto.indexKey(from: vaultKey, vaultID: header.vaultId))), "index key")
        #expect(!onDisk(bytes(wrapKey)), "wrap key")
        #expect(!onDisk(bytes(documentKey)), "document key")
    }
}
