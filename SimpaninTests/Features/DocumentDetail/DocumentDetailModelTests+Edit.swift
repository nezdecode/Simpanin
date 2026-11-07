//
//  DocumentDetailModelTests+Edit.swift
//  SimpaninTests
//
//  Created by Inez Amanda on 7/11/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import Testing
import VaultCore

@testable import Simpanin

/// After Edit dokumen saved: the screen shows the edited document, read again.
extension DocumentDetailModelTests {
    /// The screen's document after Edit dokumen wrote this label and name.
    func edit(_ detail: DocumentDetailModel, label: String = "Kantor", name: String = "ANI") async throws {
        var values = Self.ktpFields.values
        values[FieldKey.name] = name
        try await store.editDocument(
            detail.document.id, type: .ktp, label: label, expiry: nil, pinned: false, fields: DocumentFields(values))
    }

    @Test func anEditReplacesTheShownDocumentAndFields() async throws {
        let detail = try await loaded()
        try await edit(detail)
        await detail.edited()
        #expect(detail.phase == .loaded)
        #expect(detail.document.label == "Kantor")
        #expect(value(detail, FieldKey.name) == "ANI")
        #expect(detail.toast.map { String(localized: $0.title) } == "Perubahan disimpan")
        // An edit never changes the pages, so they aren't decrypted again.
        #expect(await store.pageReads.count == 1)
    }

    @Test func aFailedReadAfterAnEditShowsTheLoadErrorNeverTheOldValues() async throws {
        let detail = try await loaded()
        try await edit(detail)
        await store.setLoadFailure(.fileUnavailable)
        await detail.edited()
        #expect(detail.phase == .failed)
        #expect(detail.toast == nil)
        // Coba lagi reads the edited document, not only its fields.
        await store.setLoadFailure(nil)
        await detail.load()
        #expect(detail.document.label == "Kantor")
        #expect(value(detail, FieldKey.name) == "ANI")
    }

    @Test func unreadableFieldsAfterAnEditShowTheLoadError() async throws {
        let detail = try await loaded()
        try await edit(detail)
        await store.setUnreadable(detail.document.id)
        await detail.edited()
        #expect(detail.phase == .failed)
        #expect(detail.rows.allSatisfy { $0.value == nil })
    }

    @Test func openingEditMasksTheNumber() async throws {
        let detail = try await loaded()
        detail.toggleNumber()
        detail.editOpened()
        #expect(!detail.numberShown)
    }

    @Test func onlyALoadedLiveDocumentCanBeEdited() async throws {
        let detail = try await model()
        #expect(!detail.canEdit)
        #expect(detail.fieldsToEdit == nil)
        await detail.load()
        #expect(detail.canEdit)
        #expect(detail.fieldsToEdit == Self.ktpFields)
    }
}
