//
//  EditDocumentModelTests.swift
//  SimpaninTests
//
//  Created by Inez Amanda on 5/11/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import Parsers
import Testing
import VaultCore

@testable import Simpanin

/// Edit dokumen. Synthetic values only; NIKs start with 00.
@MainActor
@Suite("Edit document")
struct EditDocumentModelTests {
    private static let nik = "0012341708900001"
    private static let otherNIK = "0012341708900002"

    /// A saved document and the edit model opened on it.
    private func edit(
        _ store: FakeDocuments, type: DocumentType = .ktp, label: String? = nil, expiry: CalendarDate? = nil,
        pinned: Bool = false, fields: [String: String]
    ) async throws -> EditDocumentModel {
        let id = try await store.createDocument(
            type: type, label: label, expiry: expiry, pinned: pinned, fields: DocumentFields(fields), pages: [])
        let document = try #require(await store.document(id))
        return EditDocumentModel(document: document, fields: DocumentFields(fields), store: store)
    }

    @Test func opensOnTheSavedValuesWithDatesDayFirst() async throws {
        let model = try await edit(
            FakeDocuments(), label: "Ibu", fields: [FieldKey.nik: Self.nik, FieldKey.birthDate: "1990-08-17"])
        #expect(model.form.values[FieldKey.birthDate] == "17-08-1990")
        #expect(model.label == "Ibu")
        #expect(!model.hasChanges)
    }

    @Test func savesTheLabelExpiryAndFields() async throws {
        let store = FakeDocuments()
        let model = try await edit(
            store, type: .simA, label: "Saya", expiry: CalendarDate(year: 2030, month: 1, day: 1),
            fields: [FieldKey.simNumber: "00123456789012", FieldKey.name: "BUDI"])
        model.label = "Kantor"
        model.setValue("ANI", for: FieldKey.name)
        let expiry = try #require(CalendarDate(year: 2031, month: 2, day: 28))
        model.setExpiry(expiry)
        #expect(await model.save())
        let saved = try #require(await store.document(model.document.id))
        #expect(saved.label == "Kantor")
        #expect(saved.expiry == expiry)
        #expect(await store.edited.last?.values == [FieldKey.simNumber: "00123456789012", FieldKey.name: "ANI"])
    }

    @Test func keepsTheTypePinnedAndKeysTheTypeDoesNotShow() async throws {
        let store = FakeDocuments()
        let model = try await edit(store, pinned: true, fields: [FieldKey.nik: Self.nik, "plate": "B 1234 XYZ"])
        model.setValue("ANI", for: FieldKey.name)
        #expect(await model.save())
        let saved = try #require(await store.document(model.document.id))
        #expect(saved.type == .ktp)
        #expect(saved.pinned)
        #expect(await store.edited.last?.values["plate"] == "B 1234 XYZ")
    }

    @Test func anExpiryTheTypeDoesNotShowIsKept() async throws {
        let store = FakeDocuments()
        let expiry = try #require(CalendarDate(year: 2030, month: 8, day: 17))
        let model = try await edit(store, expiry: expiry, fields: [FieldKey.nik: Self.nik])
        #expect(!model.hasExpiry)
        model.setExpiry(nil)
        model.label = "Ibu"
        #expect(await model.save())
        #expect(await store.document(model.document.id)?.expiry == expiry)
    }

    @Test func anEmptiedLabelIsSavedAsNone() async throws {
        let store = FakeDocuments()
        let model = try await edit(store, label: "Ibu", fields: [FieldKey.nik: Self.nik])
        model.label = "  "
        #expect(await model.save())
        #expect(await store.document(model.document.id)?.label == nil)
    }

    @Test func nothingChangedSavesNothing() async throws {
        let store = FakeDocuments()
        let model = try await edit(store, label: "Ibu", fields: [FieldKey.nik: Self.nik])
        // A field writes its value back when it takes focus; that isn't a change.
        model.setValue(Self.nik, for: FieldKey.nik)
        #expect(!model.hasChanges)
        #expect(await !model.save())
        #expect(await store.edited.isEmpty)
    }

    @Test func aLabelOnlyChangeCountsAsAChange() async throws {
        let model = try await edit(FakeDocuments(), fields: [FieldKey.nik: Self.nik])
        model.label = "Ibu"
        #expect(model.hasChanges)
    }

    @Test func aStoredValueThatFailsTodayIsShownButDoesNotBlock() async throws {
        let store = FakeDocuments()
        let stored = [FieldKey.nik: "0012", FieldKey.name: " BUDI "]
        let model = try await edit(store, fields: stored)
        model.label = "Ibu"
        #expect(model.saveStep() == .save)
        #expect(model.form.note(for: FieldKey.nik) == .refusal(.nikLength))
        #expect(await model.save())
        #expect(await store.edited.last?.values == stored)
    }

    @Test func aChangedWrongValueIsRefused() async throws {
        let store = FakeDocuments()
        let model = try await edit(store, fields: [FieldKey.nik: Self.nik])
        model.setValue("00123", for: FieldKey.nik)
        #expect(model.saveStep() == .refuse(FieldKey.nik))
        #expect(await !model.save())
        #expect(await store.edited.isEmpty)
    }

    @Test func asksAboutAnEmptyNIKOnlyWhenThisEditEmptiedIt() async throws {
        let model = try await edit(FakeDocuments(), fields: [FieldKey.nik: Self.nik])
        model.setValue("", for: FieldKey.nik)
        #expect(model.saveStep() == .askNIK)
        model.alertAnswered()
        #expect(model.saveStepWithoutNIK() == .save)
    }

    @Test func anAlreadyEmptyNIKIsNotAskedAbout() async throws {
        let model = try await edit(FakeDocuments(), fields: [FieldKey.name: "BUDI"])
        model.setValue("ANI", for: FieldKey.name)
        #expect(model.saveStep() == .save)
    }

    @Test func anEmptiedNIKIsRemoved() async throws {
        let store = FakeDocuments()
        let model = try await edit(store, fields: [FieldKey.nik: Self.nik, FieldKey.name: "BUDI"])
        model.setValue("", for: FieldKey.nik)
        #expect(await model.save())
        #expect(await store.edited.last?.values == [FieldKey.name: "BUDI"])
    }

    @Test func anUnchangedNumberIsNotCheckedForDuplicates() async throws {
        let store = FakeDocuments()
        _ = try await store.createDocument(
            type: .ktp, label: nil, expiry: nil, pinned: false, fields: DocumentFields([FieldKey.nik: Self.nik]),
            pages: [])
        let model = try await edit(store, fields: [FieldKey.nik: Self.nik])
        model.label = "Ibu"
        #expect(await model.save())
        #expect(await store.fieldReads.isEmpty)
    }

    @Test func aChangedNumberMatchingAnotherDocumentWarns() async throws {
        let store = FakeDocuments()
        _ = try await store.createDocument(
            type: .ktp, label: nil, expiry: nil, pinned: false, fields: DocumentFields([FieldKey.nik: Self.nik]),
            pages: [])
        let model = try await edit(store, fields: [FieldKey.nik: Self.otherNIK])
        model.setValue(Self.nik, for: FieldKey.nik)
        #expect(await !model.save())
        #expect(model.duplicate?.name == .ktp)
        #expect(await store.edited.isEmpty)
        model.acceptDuplicate()
        #expect(await model.save())
        #expect(await store.edited.last?.values[FieldKey.nik] == Self.nik)
    }

    /// The check compares other documents; the one being edited is never decrypted for it.
    @Test func aChangedNumberNeverDecryptsTheEditedDocument() async throws {
        let store = FakeDocuments()
        let other = try await store.createDocument(
            type: .ktp, label: nil, expiry: nil, pinned: false, fields: DocumentFields([FieldKey.nik: Self.nik]),
            pages: [])
        let model = try await edit(store, fields: [FieldKey.nik: Self.otherNIK])
        model.setValue("0012341708900003", for: FieldKey.nik)
        #expect(await model.save())
        #expect(await store.fieldReads == [other])
    }

    /// A lock takes the sheet away mid-check and cancels its save; nothing is written after that.
    @Test func aCancelledSaveWritesNothing() async throws {
        let store = FakeDocuments()
        _ = try await store.createDocument(
            type: .ktp, label: nil, expiry: nil, pinned: false, fields: DocumentFields([FieldKey.nik: Self.nik]),
            pages: [])
        let model = try await edit(store, fields: [FieldKey.nik: Self.otherNIK])
        model.setValue("0012341708900003", for: FieldKey.nik)
        await store.gateNextFieldsRead()
        let save = Task { await model.save() }
        #expect(await store.waitUntilReadingFields())
        save.cancel()
        await store.releaseFieldsRead()
        #expect(await !save.value)
        #expect(await store.edited.isEmpty)
    }

    @Test func anEditedBirthDateThatDisagreesIsMarked() async throws {
        // The NIK holds 17-08-1990.
        let model = try await edit(
            FakeDocuments(), fields: [FieldKey.nik: Self.nik, FieldKey.birthDate: "1990-08-17"])
        model.setValue("18081990", for: FieldKey.birthDate)
        #expect(model.form.note(for: FieldKey.birthDate) == .mark(.disagreesWithBirthDate))
    }

    @Test func aSecondTapWritesOnce() async throws {
        let store = FakeDocuments()
        let model = try await edit(store, fields: [FieldKey.nik: Self.nik])
        model.label = "Ibu"
        await store.gateNextEdit()
        async let first = model.save()
        #expect(await store.waitUntilEditing())
        #expect(await !model.save())
        await store.releaseEdit()
        #expect(await first)
        #expect(await store.edited.count == 1)
    }

    @Test func aFailedSaveKeepsTheEdits() async throws {
        let store = FakeDocuments()
        let model = try await edit(store, fields: [FieldKey.nik: Self.nik])
        model.setValue("ANI", for: FieldKey.name)
        await store.setFailure(.fileUnavailable)
        #expect(await !model.save())
        #expect(model.saveError == .saveFailed)
        #expect(model.form.values[FieldKey.name] == "ANI")
        #expect(model.hasChanges)
    }

    @Test func aFullDiskShowsTheStorageAlert() async throws {
        let store = FakeDocuments()
        let model = try await edit(store, fields: [FieldKey.nik: Self.nik])
        model.label = "Ibu"
        await store.setFailure(.storageFull)
        #expect(await !model.save())
        #expect(model.saveError == .storageFullOnSave)
    }

    @Test func onSavedRunsOnlyOnceTheVaultHasTheEdit() async throws {
        let store = FakeDocuments()
        let model = try await edit(store, fields: [FieldKey.nik: Self.nik])
        model.label = "Ibu"
        await store.setFailure(.fileUnavailable)
        var saved = 0
        _ = await model.save { saved += 1 }
        #expect(saved == 0)
        await store.setFailure(nil)
        _ = await model.save { saved += 1 }
        #expect(saved == 1)
    }
}
