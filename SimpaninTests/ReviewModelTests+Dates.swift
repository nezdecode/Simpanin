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
}
