//
//  DocumentDetailModelTests+Deleted.swift
//  SimpaninTests
//
//  Created by Inez Amanda on 30/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import Testing
import VaultCore

@testable import Simpanin

/// A document opened from Baru dihapus: read-only until it's restored.
extension DocumentDetailModelTests {
    func loadedDeleted(
        onRestore: @escaping (DocumentID) async -> Bool = { _ in true },
        onDeletePermanently: @escaping (DocumentID) async -> Bool = { _ in true }
    ) async throws -> DocumentDetailModel {
        let id = try await store.createDocument(
            type: .ktp, label: nil, expiry: nil, pinned: false, fields: Self.ktpFields, pages: [Self.page()])
        try await store.delete(id)
        let document = try #require(await store.recentlyDeleted().first { $0.id == id })
        let detail = DocumentDetailModel(
            document: document, store: store, pageReader: store, clipboard: clipboard, onDelete: { _ in true },
            onRestore: onRestore, onDeletePermanently: onDeletePermanently)
        await detail.load()
        return detail
    }

    @Test func aDeletedNumberCannotBeShown() async throws {
        let detail = try await loadedDeleted()
        #expect(detail.isDeleted)
        let row = try #require(detail.rows.first { $0.key == FieldKey.nik })
        #expect(!row.canReveal)
        detail.toggleNumber()
        #expect(!detail.numberShown)
        #expect(value(detail, FieldKey.nik) == "0012 •••• •••• 0001")
    }

    @Test func aDeletedDocumentHasNoCopy() async throws {
        let detail = try await loadedDeleted()
        #expect(detail.rows.allSatisfy { !$0.canCopy })
        detail.copy(FieldKey.nik)
        detail.copy(FieldKey.name)
        #expect(clipboard.copied.isEmpty)
        #expect(detail.toast == nil)
    }

    @Test func aDeletedDocumentStillReadsItsPages() async throws {
        let detail = try await loadedDeleted()
        #expect(detail.phase == .loaded)
        #expect(shownCount(detail) == 1)
    }

    @Test func restoreClosesOnlyWhenItSucceeded() async throws {
        var restored: [DocumentID] = []
        var succeeds = false
        let detail = try await loadedDeleted(onRestore: { id in
            restored.append(id)
            return succeeds
        })
        await detail.restore()
        #expect(!detail.closed)
        succeeds = true
        await detail.restore()
        #expect(detail.closed)
        #expect(restored == [detail.document.id, detail.document.id])
    }

    @Test func deletePermanentlyClosesOnlyWhenItSucceeded() async throws {
        var purged: [DocumentID] = []
        var succeeds = false
        let detail = try await loadedDeleted(onDeletePermanently: { id in
            purged.append(id)
            return succeeds
        })
        await detail.deletePermanently()
        #expect(!detail.closed)
        succeeds = true
        await detail.deletePermanently()
        #expect(detail.closed)
        #expect(purged == [detail.document.id, detail.document.id])
    }
}
