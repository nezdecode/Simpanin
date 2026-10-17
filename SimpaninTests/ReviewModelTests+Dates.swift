//
//  ReviewModelTests+Dates.swift
//  SimpaninTests
//
//  Created by Inez Amanda on 17/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import CoreGraphics
import Foundation
import Parsers
import Testing
import VaultCore

@testable import Simpanin

/// Dates as typed, and the NIK checked against the birth date.
extension ReviewModelTests {
    /// A birth date can't be in the future, so Simpan refuses one and says why under the field.
    @Test func aFutureBirthDateIsRefusedWithAReason() async throws {
        let store = FakeDocuments()
        let review = model(store)
        review.load(Self.ktp, pages: [try page()])
        review.setValue("17-08-2999", for: FieldKey.birthDate)
        // Shown as soon as the date is complete, not only when Simpan is tapped.
        #expect(review.problems[FieldKey.birthDate] == .birthDateInFuture)
        #expect(await !review.save())
        #expect(review.problems[FieldKey.birthDate] == .birthDateInFuture)
        #expect(await store.created.isEmpty)
        review.setValue("17-08-1990", for: FieldKey.birthDate)
        #expect(review.problems.isEmpty)
    }

    /// Half-typed dates aren't judged; a complete one that can't exist says so at once.
    @Test func onlyACompleteDateIsChecked() throws {
        let review = model()
        review.load(Self.ktp, pages: [try page()])
        review.setValue("31-02-19", for: FieldKey.birthDate)
        #expect(review.problems.isEmpty)
        review.setValue("31-02-1990", for: FieldKey.birthDate)
        #expect(review.problems[FieldKey.birthDate] == .notADate)
        review.setValue("28-02-1990", for: FieldKey.birthDate)
        #expect(review.problems.isEmpty)
    }

    /// The NIK holds two digits of the year, so agreeing with it can't clear a mark on an implausible
    /// century: 1890 matches a NIK made for 1990.
    @Test func aNIKThatAgreesKeepsAnImplausibleYearMarked() throws {
        let review = model()
        let old = ParsedDocument(
            type: .ktp,
            fields: DocumentFields([FieldKey.nik: "0012341708900001", FieldKey.birthDate: "1890-08-17"]),
            expiry: nil, needsCheck: [FieldKey.birthDate])
        review.load(old, pages: [try page()])
        review.setValue("0012341708900001", for: FieldKey.nik)
        #expect(review.marked.contains(FieldKey.birthDate))
    }

    /// Typed on a number pad: the dashes come by themselves, and only before a digit, so deleting one works.
    @Test func typedDatesGetDashes() {
        #expect(ReviewModel.typedDate("17") == "17")
        #expect(ReviewModel.typedDate("170") == "17-0")
        #expect(ReviewModel.typedDate("17081990") == "17-08-1990")
        #expect(ReviewModel.typedDate("17-08-1990") == "17-08-1990")
        #expect(ReviewModel.typedDate("17/08/19901") == "17-08-1990")
    }

    /// An edit that makes the birth date and the NIK disagree marks both: either could be the wrong one.
    @Test func aNIKAndBirthDateThatDisagreeAreMarked() throws {
        let review = model()
        review.load(Self.ktp, pages: [try page()])
        review.setValue("18-08-1990", for: FieldKey.birthDate)
        #expect(review.marked.isSuperset(of: [FieldKey.nik, FieldKey.birthDate]))
        review.setValue("17-08-1990", for: FieldKey.birthDate)
        #expect(review.marked.isDisjoint(with: [FieldKey.nik, FieldKey.birthDate]))
        review.setValue("0012341808900001", for: FieldKey.nik)
        #expect(review.marked.isSuperset(of: [FieldKey.nik, FieldKey.birthDate]))
    }

    /// A NIK that isn't 16 digits is judged when the field is left, not while it's being typed.
    @Test func aNIKOfTheWrongLengthIsJudgedWhenTheFieldIsLeft() throws {
        let review = model()
        review.load(Self.ktp, pages: [try page()])
        review.setValue("00123417089000", for: FieldKey.nik)
        #expect(review.problems.isEmpty)
        review.fieldLeft(FieldKey.nik)
        #expect(review.problems[FieldKey.nik] == .nikLength)
        review.setValue("0012341708900001", for: FieldKey.nik)
        review.fieldLeft(FieldKey.nik)
        #expect(review.problems.isEmpty)
    }

    /// A wrong value the scan read shows its reason as soon as the screen opens.
    @Test func aWrongNIKFromTheScanShowsAtOnce() throws {
        let review = model()
        let short = ParsedDocument(
            type: .ktp, fields: DocumentFields([FieldKey.nik: "001234170890000"]), expiry: nil, needsCheck: [])
        review.load(short, pages: [try page()])
        #expect(review.problems[FieldKey.nik] == .nikLength)
    }

    @Test func simpanRefusesAWrongNIK() async throws {
        let store = FakeDocuments()
        let review = model(store)
        review.load(Self.ktp, pages: [try page()])
        review.setValue("001234170890000", for: FieldKey.nik)
        #expect(await !review.save())
        #expect(review.problems[FieldKey.nik] == .nikLength)
        #expect(await store.created.isEmpty)
    }

    /// Simpan goes to the first wrong field in screen order; the others show their reasons where they are.
    @Test func theFirstProblemIsTheFirstFieldOnScreen() throws {
        let review = model()
        review.load(Self.ktp, pages: [try page()])
        #expect(review.firstProblem() == nil)
        review.setValue("17-08-2999", for: FieldKey.birthDate)
        review.setValue("00123", for: FieldKey.nik)
        #expect(review.firstProblem() == FieldKey.nik)
        #expect(review.problems[FieldKey.birthDate] == .birthDateInFuture)
    }

    /// An empty NIK is asked about, never refused: an old photo can be blurred just there.
    @Test func anEmptyNIKIsAskedAboutNotRefused() async throws {
        let store = FakeDocuments()
        let review = model(store)
        review.load(Self.ktp, pages: [try page()])
        #expect(!review.nikMissing)
        review.setValue("", for: FieldKey.nik)
        #expect(review.nikMissing)
        #expect(review.firstProblem() == nil)
        #expect(await review.save())
        review.load(Self.sim, pages: [try page()])
        #expect(!review.nikMissing)
    }

    /// A field gets its own value written back when it takes focus; that isn't an edit, so the reason stays.
    @Test func writingTheSameValueKeepsTheReason() throws {
        let review = model()
        review.load(Self.ktp, pages: [try page()])
        review.setValue("00123", for: FieldKey.nik)
        review.fieldLeft(FieldKey.nik)
        review.setValue("00123", for: FieldKey.nik)
        #expect(review.problems[FieldKey.nik] == .nikLength)
    }

    /// An empty field writes "" back when it takes focus; that isn't an edit either.
    @Test func anEmptyFieldWrittenBackStaysUntouched() throws {
        let review = model()
        let noNIK = ParsedDocument(
            type: .ktp, fields: DocumentFields([FieldKey.name: "BUDI CONTOH"]), expiry: nil, needsCheck: [FieldKey.nik])
        review.load(noNIK, pages: [try page()])
        review.setValue("", for: FieldKey.nik)
        #expect(review.marked.contains(FieldKey.nik))
        #expect(!review.hasUserChanges)
    }
}
