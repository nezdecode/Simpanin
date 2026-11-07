//
//  DocumentFormTests.swift
//  SimpaninTests
//
//  Created by Inez Amanda on 5/11/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import Testing
import VaultCore

@testable import Simpanin

/// What the form saves and counts as changed. Synthetic values only; NIKs start with 00.
@Suite("Document form")
struct DocumentFormTests {
    private static let nik = "0012341708900001"

    private func saved(_ values: [String: String]) -> DocumentForm {
        DocumentForm(type: .ktp, stored: DocumentFields(values))
    }

    @Test func aSavedDocumentShowsItsDatesDayFirst() {
        let form = saved([FieldKey.nik: Self.nik, FieldKey.birthDate: "1990-08-17"])
        #expect(form.values[FieldKey.birthDate] == "17-08-1990")
        #expect(form.values[FieldKey.nik] == Self.nik)
        #expect(form.changedKeys.isEmpty)
    }

    @Test func anUnchangedFieldIsSavedAsStored() {
        // Untrimmed, and a date that doesn't read as one: neither is touched when another field changes.
        let stored = [FieldKey.nik: Self.nik, FieldKey.name: " BUDI CONTOH ", FieldKey.birthDate: "1990-8-17x"]
        var form = saved(stored)
        #expect(form.savedFields() == stored)
        form.setValue("0012341708900002", for: FieldKey.nik)
        var expected = stored
        expected[FieldKey.nik] = "0012341708900002"
        #expect(form.savedFields() == expected)
    }

    @Test func anEmptiedFieldIsRemoved() {
        var form = saved([FieldKey.nik: Self.nik, FieldKey.name: "BUDI CONTOH"])
        form.setValue("", for: FieldKey.name)
        #expect(form.savedFields() == [FieldKey.nik: Self.nik])
    }

    @Test func aChangedFieldIsTrimmedAndStoredYearFirst() {
        var form = saved([FieldKey.nik: Self.nik])
        form.setValue(" ANI ", for: FieldKey.name)
        form.setValue("17081990", for: FieldKey.birthDate)
        #expect(form.savedFields()[FieldKey.name] == "ANI")
        #expect(form.savedFields()[FieldKey.birthDate] == "1990-08-17")
    }

    @Test func keysTheTypeDoesNotShowAreKept() {
        var form = saved([FieldKey.nik: Self.nik, "plate": "B 1234 XYZ"])
        form.setValue("ANI", for: FieldKey.name)
        #expect(form.savedFields()["plate"] == "B 1234 XYZ")
    }

    @Test func anEmptyFieldTypedInAndClearedIsNotAChange() {
        var form = saved([FieldKey.nik: Self.nik])
        form.setValue("A", for: FieldKey.name)
        #expect(form.changedKeys == [FieldKey.name])
        form.setValue("", for: FieldKey.name)
        #expect(form.changedKeys.isEmpty)
    }

    @Test func aStoredValueThatFailsTodayIsShownButBlocksOnlyOnceChanged() {
        var form = saved([FieldKey.nik: "0012"])
        #expect(form.firstProblem(among: form.changedKeys) == nil)
        #expect(form.note(for: FieldKey.nik) == .refusal(.nikLength))
        form.setValue("00123", for: FieldKey.nik)
        #expect(form.firstProblem(among: form.changedKeys) == FieldKey.nik)
    }

    @Test func theNIKCountsAsEmptiedOnlyWhenThisEditEmptiedIt() {
        var empty = saved([FieldKey.name: "BUDI CONTOH"])
        #expect(empty.nikMissing)
        #expect(!empty.nikEmptied)
        empty.setValue("ANI", for: FieldKey.name)
        #expect(!empty.nikEmptied)
        var filled = saved([FieldKey.nik: Self.nik])
        filled.setValue("", for: FieldKey.nik)
        #expect(filled.nikEmptied)
    }

    @Test func aScanSavesEveryFilledFieldTrimmedAndYearFirst() {
        let form = DocumentForm(
            type: .ktp, values: [FieldKey.nik: Self.nik, FieldKey.name: " BUDI ", FieldKey.birthDate: "17-08-1990"])
        #expect(
            form.savedFields() == [FieldKey.nik: Self.nik, FieldKey.name: "BUDI", FieldKey.birthDate: "1990-08-17"])
    }

    @Test func aLabelThatLooksLikeANumberIsFlagged() {
        for (label, flagged) in [("Ibu", false), ("KTP 12", false), ("3171 0890", true), ("0012341708900001", true)] {
            #expect(DocumentForm.looksLikeANumber(label) == flagged, "\(label)")
        }
    }
}
