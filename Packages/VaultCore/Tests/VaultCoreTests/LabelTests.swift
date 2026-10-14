//
//  LabelTests.swift
//  VaultCoreTests
//
//  Created by Inez Amanda on 15/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import Testing

@testable import VaultCore

/// The label tells documents apart on the list, so it lives in the index. It can name people
/// ("SIM Ibu"), so it must never reach the plaintext projection.
@Suite("Labels")
struct LabelTests {
    /// Distinctive, so a search through the files can't match anything else.
    static let label = "Ibu-label-7Q"

    @Test func createKeepsTheLabelAcrossAReopen() async throws {
        let vault = try TestVault()
        let store = vault.makeStore()
        try await store.open()
        let labelled = try await store.createDocument(
            type: .ktp, label: Self.label, expiry: nil, pinned: false,
            fields: Synthetic.ktpFields, pages: [Synthetic.page("front")])
        let plain = try await store.createDocument(
            type: .sim, expiry: nil, pinned: false, fields: Synthetic.simFields, pages: [])
        #expect(try await store.document(labelled).label == Self.label)
        #expect(try await store.document(plain).label == nil)

        let reopened = vault.makeStore()
        try await reopened.open()
        #expect(try await reopened.documents().map(\.label) == [Self.label, nil])
    }

    @Test func editChangesAndClearsTheLabel() async throws {
        let vault = try TestVault()
        let store = vault.makeStore()
        try await store.open()
        let id = try await store.createDocument(
            type: .ktp, expiry: nil, pinned: false, fields: Synthetic.ktpFields, pages: [])
        try await store.editDocument(
            id, type: .ktp, label: "Kantor", expiry: nil, pinned: false, fields: Synthetic.ktpFields)
        #expect(try await store.document(id).label == "Kantor")
        try await store.editDocument(
            id, type: .ktp, label: nil, expiry: nil, pinned: false, fields: Synthetic.ktpFields)
        #expect(try await store.document(id).label == nil)
    }

    @Test func deletedDocumentsKeepTheirLabel() async throws {
        let vault = try TestVault()
        let store = vault.makeStore()
        try await store.open()
        let id = try await store.createDocument(
            type: .npwp, label: "Kantor", expiry: nil, pinned: false, fields: DocumentFields(), pages: [])
        try await store.delete(id)
        #expect(try await store.recentlyDeleted().map(\.label) == ["Kantor"])
        try await store.restore(id)
        #expect(try await store.document(id).label == "Kantor")
    }

    @Test func labelIsNeverWrittenInPlaintext() async throws {
        let vault = try TestVault()
        let store = vault.makeStore()
        try await store.open()
        let id = try await store.createDocument(
            type: .sim, label: Self.label, expiry: Synthetic.simExpiry, pinned: false,
            fields: Synthetic.simFields, pages: [Synthetic.page("sim")])
        try await store.editDocument(
            id, type: .sim, label: Self.label, expiry: Synthetic.simExpiry, pinned: true,
            fields: Synthetic.simFields)
        #expect(try vault.projection().documents.map(\.id) == [id])
        for file in try vault.allFiles() {
            let data = try Data(contentsOf: file)
            #expect(!data.contains(bytes: Data(Self.label.utf8)), "label in \(file.lastPathComponent)")
        }
    }

    @Test func indexIsWrittenAsSchemaVersion2() async throws {
        let vault = try TestVault()
        let store = vault.makeStore()
        try await store.open()
        _ = try await store.createDocument(
            type: .ktp, label: Self.label, expiry: nil, pinned: false, fields: Synthetic.ktpFields, pages: [])
        let index = try await vault.readIndex(at: vault.indexURL)
        #expect(index.schemaVersion == 2)
        #expect(index.documents.map(\.label) == [Self.label])
    }

    @Test func recoveryFromPagesHasNoLabel() async throws {
        // The label lives only in the index, like the fields, so it can't come back from pages.
        let vault = try TestVault()
        let store = vault.makeStore()
        try await store.open()
        _ = try await store.createDocument(
            type: .ktp, label: Self.label, expiry: nil, pinned: false,
            fields: Synthetic.ktpFields, pages: [Synthetic.page("front")])
        try FileManager.default.removeItem(at: vault.indexURL)
        if FileManager.default.fileExists(atPath: vault.previousIndexURL.path) {
            try FileManager.default.removeItem(at: vault.previousIndexURL)
        }
        let recovered = vault.makeStore()
        #expect(try await recovered.open().recoveredFromPages)
        #expect(try await recovered.documents().map(\.label) == [nil])
    }
}
