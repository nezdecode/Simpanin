//
//  ReviewModelTests+Reasons.swift
//  SimpaninTests
//
//  Created by Inez Amanda on 19/10/26.
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

/// What shows under each value: a refusal, or "Periksa lagi" with its first reason.
extension ReviewModelTests {
    static let confirmedKTP = ParsedDocument(
        type: .ktp,
        fields: DocumentFields([
            FieldKey.nik: "0012341708900001", FieldKey.name: "BUDI CONTOH", FieldKey.birthDate: "1990-08-17",
        ]),
        expiry: nil, birthDateConfirmed: true)

    static let confirmedSIM = ParsedDocument(
        type: .simA,
        fields: DocumentFields([
            FieldKey.simNumber: "0012341708900001", FieldKey.name: "BUDI CONTOH", FieldKey.birthDate: "1990-08-17",
        ]),
        expiry: CalendarDate(year: 2029, month: 7, day: 29), birthDateConfirmed: true)

    @Test func aMarkKeepsEveryReasonAndShowsTheTopOne() throws {
        let review = model()
        let scan = ParsedDocument(
            type: .ktp, fields: Self.confirmedKTP.fields, expiry: nil,
            reasons: [FieldKey.nik: [.lookalike, .disagreesWithBirthDate]])
        review.loadScan(scan, pages: [try page()])
        #expect(review.marked[FieldKey.nik] == [.lookalike, .disagreesWithBirthDate])
        #expect(review.note(for: FieldKey.nik) == .mark(.disagreesWithBirthDate))
        #expect(review.note(for: FieldKey.name) == nil)
    }

    @Test func editingAFieldDropsItsReasons() throws {
        let review = model()
        review.loadScan(Self.ktp, pages: [try page()])
        review.setValue("BUDI CONTOH", for: FieldKey.name)
        #expect(review.marked[FieldKey.name] == nil)
        #expect(review.note(for: FieldKey.name) == nil)
    }

    @Test func anEditThatMakesTheNIKAndBirthDateDisagreeMarksBoth() throws {
        let review = model()
        review.loadScan(Self.confirmedKTP, pages: [try page()])
        review.setValue("18-08-1990", for: FieldKey.birthDate)
        #expect(review.note(for: FieldKey.nik) == .mark(.disagreesWithBirthDate))
        #expect(review.note(for: FieldKey.birthDate) == .mark(.disagreesWithBirthDate))
    }

    /// Before 19 Oct the agreement cleared the NIK's mark entirely, so a corrected digit was saved unmarked.
    @Test func anEditThatMakesThemAgreeKeepsTheNIKsOtherReason() throws {
        let review = model()
        let scan = ParsedDocument(
            type: .ktp,
            fields: DocumentFields([FieldKey.nik: "0012341708900001", FieldKey.birthDate: "1990-08-18"]),
            expiry: nil,
            reasons: [
                FieldKey.nik: [.lookalike, .disagreesWithBirthDate], FieldKey.birthDate: [.disagreesWithBirthDate],
            ])
        review.loadScan(scan, pages: [try page()])
        review.setValue("17-08-1990", for: FieldKey.birthDate)
        #expect(review.note(for: FieldKey.nik) == .mark(.lookalike))
        #expect(review.note(for: FieldKey.birthDate) == nil)
    }

    @Test func anEditThatMakesTheSIMNumberAndBirthDateDisagreeMarksBoth() throws {
        let review = model()
        review.loadScan(Self.confirmedSIM, pages: [try page()])
        review.setValue("18-08-1990", for: FieldKey.birthDate)
        #expect(review.note(for: FieldKey.simNumber) == .mark(.disagreesWithBirthDate))
        review.setValue("17-08-1990", for: FieldKey.birthDate)
        #expect(review.note(for: FieldKey.simNumber) == nil)
    }

    /// Typed on the punctuation keyboard, as it's shown.
    @Test func aSIMNumberWithDashesIsCheckedAsDigits() throws {
        let review = model()
        review.loadScan(Self.confirmedSIM, pages: [try page()])
        review.setValue("0012-3418-0890-0001", for: FieldKey.simNumber)
        #expect(review.note(for: FieldKey.birthDate) == .mark(.disagreesWithBirthDate))
    }

    /// An old number holds no birth date, so nothing is compared. This can't fail on its own: `NIK.agrees`
    /// gives nil for 14 digits, which NIKTests' aNIKWithoutADateSaysNothing guards. It shows the case here.
    @Test func anOldSIMNumberIsNeverCheckedAgainstTheBirthDate() throws {
        let review = model()
        review.loadScan(Self.sim, pages: [try page()])
        review.setValue("01-01-1990", for: FieldKey.birthDate)
        review.setValue("0000-0000-000002", for: FieldKey.simNumber)
        #expect(review.note(for: FieldKey.simNumber) == nil)
        #expect(review.note(for: FieldKey.birthDate) == nil)
    }

    @Test func birthDateMatchShowsOnlyForAConfirmedScan() throws {
        let review = model()
        review.loadScan(Self.confirmedKTP, pages: [try page()])
        #expect(review.showsBirthDateMatch)
        review.loadScan(Self.ktp, pages: [try page()])
        #expect(!review.showsBirthDateMatch)
        review.loadScan(Self.confirmedSIM, pages: [try page()])
        #expect(review.showsBirthDateMatch)
    }

    /// Each edit still agrees with the other value, so only the edit itself hides the match.
    @Test func birthDateMatchGoesAfterEditingEitherField() throws {
        for key in [FieldKey.nik, FieldKey.birthDate] {
            let review = model()
            review.loadScan(Self.confirmedKTP, pages: [try page()])
            review.setValue(key == FieldKey.nik ? "0012341708900002" : "17-08-1890", for: key)
            #expect(review.note(for: key) == nil, "\(key)")
            #expect(!review.showsBirthDateMatch, "\(key)")
        }
    }

    /// Two values the user typed say nothing about the card.
    @Test func typingAValueBackDoesntBringTheMatchBack() throws {
        let review = model()
        review.loadScan(Self.confirmedKTP, pages: [try page()])
        review.setValue("0012341708900002", for: FieldKey.nik)
        review.setValue("0012341708900001", for: FieldKey.nik)
        #expect(!review.showsBirthDateMatch)
    }

    @Test func birthDateMatchHidesWhenEitherFieldHasAMarkOrRefusal() throws {
        let review = model()
        let marked = ParsedDocument(
            type: .ktp, fields: Self.confirmedKTP.fields, expiry: nil, reasons: [FieldKey.nik: [.sexDisagrees]],
            birthDateConfirmed: true)
        review.loadScan(marked, pages: [try page()])
        #expect(!review.showsBirthDateMatch)
        let refused = ParsedDocument(
            type: .ktp, fields: DocumentFields([FieldKey.nik: "001234170890000", FieldKey.birthDate: "1990-08-17"]),
            expiry: nil, birthDateConfirmed: true)
        review.loadScan(refused, pages: [try page()])
        #expect(!review.showsBirthDateMatch)
    }

    /// The match was for the scanned type's number; another type has other fields.
    @Test func birthDateMatchGoesWithAnotherType() throws {
        let review = model()
        review.loadScan(Self.confirmedKTP, pages: [try page()])
        review.type = .simA
        #expect(!review.showsBirthDateMatch)
    }

    @Test func aNIKOfTheWrongLengthIsRefusedFromTheStart() throws {
        let review = model()
        let short = ParsedDocument(type: .ktp, fields: DocumentFields([FieldKey.nik: "00123417089000"]), expiry: nil)
        review.loadScan(short, pages: [try page()])
        #expect(review.note(for: FieldKey.nik) == .refusal(.nikLength))
    }

    @Test func aRefusalReplacesTheMark() throws {
        let review = model()
        review.loadScan(Self.ktp, pages: [try page()])
        #expect(review.note(for: FieldKey.name) == .mark(.oddCharacters))
        let scan = ParsedDocument(
            type: .ktp, fields: DocumentFields([FieldKey.nik: "00123"]), expiry: nil,
            reasons: [FieldKey.nik: [.lookalike]])
        review.loadScan(scan, pages: [try page()])
        #expect(review.note(for: FieldKey.nik) == .refusal(.nikLength))
    }

    @Test func aNoMatchScanGivesTheTypeItsReason() throws {
        let review = model()
        review.loadScan(nil, pages: [try page()])
        #expect(review.typeNote == .mark(.noDocumentRecognized))
        review.type = .ktp
        #expect(review.typeNote == nil)
    }

    @Test func aTypeChangeThatMovesTheDatesMeaningSaysSo() throws {
        let review = model()
        review.loadScan(Self.confirmedSIM, pages: [try page()])
        review.type = .simC
        #expect(review.expiryNote == nil)
        review.type = .stnk
        #expect(review.expiryNote == .dateFromAnotherType)
    }

    @Test func changingTheTypeBackRestoresTheScansExpiryReason() throws {
        let review = model()
        review.loadScan(Self.sim, pages: [try page()])
        #expect(review.expiryNote == .mark(.implausibleExpiry))
        review.type = .stnk
        #expect(review.expiryNote == .dateFromAnotherType)
        review.type = .simC
        #expect(review.expiryNote == .mark(.implausibleExpiry))
    }

    /// Switched to a SIM by hand, nothing was read, so no reason is true; "Periksa lagi" stays plain.
    @Test func aMissingExpiryWithoutAReadShowsAPlainMark() throws {
        let review = model()
        review.loadScan(Self.ktp, pages: [try page()])
        review.type = .simC
        #expect(review.expiryNote == .mark(nil))
    }

    @Test func aRescanTakesEveryReasonFromTheNewScan() throws {
        let review = model()
        review.loadScan(Self.ktp, pages: [try page()])
        review.setValue("18-08-1990", for: FieldKey.birthDate)
        review.loadScan(Self.confirmedKTP, pages: [try page()])
        #expect(review.marked.isEmpty)
        #expect(review.showsBirthDateMatch)
    }

    /// An STNK or a passport has no parser yet, so its empty date isn't a misread, whatever the SIM scan said.
    @Test func aSIMsMissingExpiryIsntMarkedOnAnotherKind() throws {
        let review = model()
        let scan = ParsedDocument(type: .simC, fields: DocumentFields([:]), expiry: nil, expiryReasons: [.notFound])
        review.loadScan(scan, pages: [try page()])
        #expect(review.expiryNote == .mark(.notFound))
        review.type = .stnk
        #expect(review.expiryNote == nil)
    }

    /// A SIM's number and birth date disagreeing says nothing about a KTP, whose NIK is another field.
    @Test func aTypeChangeHidesReasonsAboutTheOtherDocument() throws {
        let review = model()
        let scan = ParsedDocument(
            type: .simA, fields: Self.confirmedSIM.fields, expiry: nil,
            reasons: [
                FieldKey.simNumber: [.disagreesWithBirthDate],
                FieldKey.birthDate: [.disagreesWithBirthDate, .lookalike],
            ])
        review.loadScan(scan, pages: [try page()])
        review.type = .ktp
        #expect(review.note(for: FieldKey.birthDate) == .mark(.lookalike))
        review.type = .simA
        #expect(review.note(for: FieldKey.birthDate) == .mark(.disagreesWithBirthDate))
    }

    /// Once one of the two can't be compared, the other no longer disagrees with anything.
    @Test func clearingTheNIKClearsTheDisagreement() throws {
        let review = model()
        review.loadScan(Self.confirmedKTP, pages: [try page()])
        review.setValue("18-08-1990", for: FieldKey.birthDate)
        #expect(review.note(for: FieldKey.birthDate) == .mark(.disagreesWithBirthDate))
        review.setValue("", for: FieldKey.nik)
        #expect(review.marked[FieldKey.birthDate] == nil)
    }
}
