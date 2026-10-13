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

    @Test func savingTheSameDocumentTwiceKeepsTwoUnlinkedCopies() async throws {
        let vault = try TestVault()
        let store = vault.makeStore()
        try await store.open()
        let pages = [Synthetic.page("ktp-front")]
        let first = try await store.createDocument(
            type: .ktp, expiry: nil, pinned: false, fields: Synthetic.ktpFields, pages: pages)
        let second = try await store.createDocument(
            type: .ktp, expiry: nil, pinned: false, fields: Synthetic.ktpFields, pages: pages)

        #expect(first != second)
        #expect(try await store.snapshot().count == 2)
        for id in [first, second] {
            #expect(try await store.fields(of: id) == Synthetic.ktpFields)
            #expect(try await store.pages(of: id).map(\.data) == pages)
        }

        // Nothing on disk should show the two are the same, so each copy has its own key.
        let header = try vault.header()
        let vaultKey = try #require(await vault.keyStore.key(for: header.vaultId))
        let wrapKey = VaultCrypto.wrapKey(from: vaultKey, vaultID: header.vaultId)
        let entries = try await vault.readIndex(at: vault.indexURL).documents
        try #require(entries.count == 2)
        let keys = try entries.map {
            try bytes(VaultCrypto.openDocumentKey($0.sealedKey, with: wrapKey, documentID: $0.id))
        }
        #expect(keys[0] != keys[1])
        #expect(entries[0].sealedFields != entries[1].sealedFields)
        let pageContents = try entries.map { entry in
            try PageFile(decoding: Data(contentsOf: vault.pageURL(entry.pageIds[0]))).sealedContent
        }
        #expect(pageContents[0] != pageContents[1])
    }

    @Test func everyFileGetsItsProtectionClass() async throws {
        let vault = try TestVault()
        let protector = RecordingProtector()
        let store = VaultStore(
            rootDirectory: vault.root, projectionURL: vault.projectionURL, keyStore: vault.keyStore,
            clock: vault.clock, fileProtector: protector)
        try await store.open()
        let ktp = try await store.createDocument(
            type: .ktp, expiry: nil, pinned: false, fields: Synthetic.ktpFields, pages: [Synthetic.page("front")])
        let sim = try await store.createDocument(
            type: .sim, expiry: nil, pinned: false, fields: Synthetic.simFields, pages: [Synthetic.page("sim")])
        try await store.editDocument(ktp, type: .ktp, expiry: nil, pinned: true, fields: Synthetic.ktpFields)
        let back = try await store.addPage(Synthetic.page("back"), to: ktp)
        _ = try await store.replacePage(back, of: ktp, with: Synthetic.page("back-rescan"))
        try await store.delete(sim)
        try await store.deletePermanently(sim)

        // Background tasks read the projection, so only it may stay readable after first unlock.
        // The class is set on ".<name>.tmp", before the rename to <name> that keeps it.
        func name(_ url: URL) -> String {
            var url = url
            if url.pathExtension == "tmp", url.lastPathComponent.hasPrefix(".") {
                url = url.deletingLastPathComponent().appending(
                    path: String(url.deletingPathExtension().lastPathComponent.dropFirst()))
            }
            return url.path.components(separatedBy: vault.base.lastPathComponent).last ?? ""
        }
        let projection = name(vault.projectionURL)
        for call in protector.calls {
            let expected: FileProtectionClass =
                name(call.url) == projection ? .completeUntilFirstUserAuthentication : .complete
            #expect(call.protection == expected, "\(name(call.url))")
        }
        // index.prev.enc is index.enc moved aside, and a move keeps the class.
        let protected = Set(protector.calls.map { name($0.url) })
        for file in try vault.allFiles() where file.lastPathComponent != "index.prev.enc" {
            #expect(protected.contains(name(file)), "\(name(file)) was never protected")
        }
        #expect(protected.contains(projection))
    }
}
