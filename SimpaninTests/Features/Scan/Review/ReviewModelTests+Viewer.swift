//
//  ReviewModelTests+Viewer.swift
//  SimpaninTests
//
//  Created by Inez Amanda on 30/10/26.
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

/// What the page viewer shows over Periksa data.
extension ReviewModelTests {
    /// The viewer never gets a full-size scan, here as on the document screen.
    @Test func theViewerGetsAPageAtMost3000PixelsLong() async throws {
        let review = model()
        review.loadScan(Self.ktp, pages: [try page(width: 4_000)])
        let shown = try #require(await review.viewerPage(0))
        #expect(shown.width == PageViewer.maxPixelSize)
        #expect(PageViewer.maxPixelSize == 3_000)
    }

    @Test func aPageThatIsntThereGivesTheViewerNothing() async throws {
        let review = model()
        review.loadScan(Self.ktp, pages: [try page()])
        #expect(await review.viewerPage(1) == nil)
        #expect(await review.viewerPage(-1) == nil)
    }

    func keys(_ review: ReviewModel) -> [String] { review.checkedFields.map(\.key) }

    func value(_ review: ReviewModel, _ key: String) -> String?? {
        review.checkedFields.first { $0.key == key }.map(\.value)
    }

    /// Nothing marked: the number still shows, as it's what's most often checked against the card.
    @Test func numberIsAlwaysFirst() throws {
        let review = model()
        review.loadScan(Self.confirmedKTP, pages: [try page()])
        #expect(keys(review) == [FieldKey.nik])
        review.loadScan(Self.ktp, pages: [try page()])
        #expect(keys(review).first == FieldKey.nik)
    }

    @Test func markedFieldsFollowFormOrder() throws {
        let review = model()
        let marked = ParsedDocument(
            type: .ktp,
            fields: DocumentFields([
                FieldKey.nik: "0012341708900001", FieldKey.name: "BUDI C0NTOH", FieldKey.birthDate: "1990-08-17",
            ]),
            expiry: nil, reasons: [FieldKey.birthDate: [.impossibleDate], FieldKey.name: [.oddCharacters]])
        review.loadScan(marked, pages: [try page()])
        #expect(keys(review) == [FieldKey.nik, FieldKey.name, FieldKey.birthDate])
    }

    @Test func refusedFieldsAreShown() throws {
        let review = model()
        review.loadScan(Self.confirmedKTP, pages: [try page()])
        review.setValue("31-02-1990", for: FieldKey.birthDate)
        #expect(review.note(for: FieldKey.birthDate) == .refusal(.notADate))
        #expect(keys(review) == [FieldKey.nik, FieldKey.birthDate])
    }

    @Test func labelIsNeverShown() throws {
        let review = model()
        review.loadScan(Self.ktp, pages: [try page()])
        review.label = "Saya"
        #expect(!review.checkedFields.contains { $0.value == "Saya" })
        #expect(keys(review) == [FieldKey.nik, FieldKey.name])
    }

    /// Nil, which the bar says as "Belum diisi".
    @Test func emptyValueReadsBelumDiisi() throws {
        let review = model()
        review.loadScan(Self.confirmedKTP, pages: [try page()])
        review.setValue("", for: FieldKey.nik)
        #expect(value(review, FieldKey.nik) == .some(nil))
    }

    /// After a correction, what Simpan would save is what's compared with the card.
    @Test func usesTheCurrentValueNotTheRead() throws {
        let review = model()
        review.loadScan(Self.ktp, pages: [try page()])
        review.setValue("BUDI CONTOH", for: FieldKey.name)
        review.setValue("0012341708900002", for: FieldKey.nik)
        #expect(keys(review) == [FieldKey.nik])
        #expect(value(review, FieldKey.nik) == "0012341708900002")
    }

    @Test func simNumberShowsDashes() throws {
        let review = model()
        review.loadScan(Self.sim, pages: [try page()])
        review.setValue("00001234567890", for: FieldKey.simNumber)
        #expect(value(review, FieldKey.simNumber) == "0000-1234-567890")
        #expect(review.checkedFields.first?.isNumber == true)
    }

    /// As printed on the card: 16 digits together, not grouped as on the document screen.
    @Test func nikIsUngrouped() throws {
        let review = model()
        review.loadScan(Self.confirmedKTP, pages: [try page()])
        #expect(value(review, FieldKey.nik) == "0012341708900001")
        #expect(review.checkedFields.first?.isNumber == true)
    }

    /// Simpan refuses it, so the bar mustn't tidy it into something that matches the card.
    @Test func aRefusedNIKShowsAsTyped() throws {
        let review = model()
        review.loadScan(Self.confirmedKTP, pages: [try page()])
        review.setValue("0012 3417 0890 0001", for: FieldKey.nik)
        #expect(value(review, FieldKey.nik) == "0012 3417 0890 0001")
        review.setValue("abc", for: FieldKey.nik)
        #expect(value(review, FieldKey.nik) == "abc")
    }

    @Test func aSIMNumberWithOtherCharactersShowsAsTyped() throws {
        let review = model()
        review.loadScan(Self.sim, pages: [try page()])
        review.setValue("0000-1234-56789O", for: FieldKey.simNumber)
        #expect(value(review, FieldKey.simNumber) == "0000-1234-56789O")
    }

    @Test func typeWithoutANumberAndNoMarksHasNoBar() throws {
        let review = model()
        review.loadScan(nil, pages: [try page()])
        review.type = .passport
        #expect(review.checkedFields.isEmpty)
    }

    @Test func noFieldsNoBar() throws {
        let review = model()
        review.loadScan(nil, pages: [try page()])
        #expect(review.type == .other)
        #expect(review.checkedFields.isEmpty)
    }

    /// Comparing the read date with the printed one needs the card too.
    @Test func markedExpiryIsShownLast() throws {
        let review = model()
        let marked = ParsedDocument(
            type: .simC,
            fields: DocumentFields([FieldKey.simNumber: "0000-0000-000001", FieldKey.name: "BUDI C0NTOH"]),
            expiry: CalendarDate(year: 2027, month: 1, day: 4), reasons: [FieldKey.name: [.oddCharacters]],
            expiryReasons: [.implausibleExpiry])
        review.loadScan(marked, pages: [try page()])
        #expect(keys(review) == [FieldKey.simNumber, FieldKey.name, ReviewModel.CheckedField.expiryKey])
    }

    /// A SIM with no date read is marked; the bar says so rather than leave it out.
    @Test func emptyMarkedExpiryReadsBelumDiisi() throws {
        let review = model()
        review.loadScan(nil, pages: [try page()])
        review.type = .simC
        #expect(value(review, ReviewModel.CheckedField.expiryKey) == .some(nil))
    }

    @Test func unmarkedExpiryIsNotShown() throws {
        let review = model()
        let read = ParsedDocument(
            type: .simC, fields: DocumentFields([FieldKey.simNumber: "0000-0000-000001"]),
            expiry: CalendarDate(year: 2027, month: 1, day: 4))
        review.loadScan(read, pages: [try page()])
        #expect(keys(review) == [FieldKey.simNumber])
    }

    /// dd-mm-yyyy, as the card prints it, under the title the form gives it.
    @Test func expiryShowsAsPrinted() throws {
        let review = model()
        review.loadScan(Self.sim, pages: [try page()])
        let expiry = try #require(review.checkedFields.last)
        #expect(expiry.value == "04-01-2027")
        #expect(expiry.title == "review.validUntil")
        #expect(!expiry.isNumber)
        // A date read for a SIM is noted on an STNK too, under its "Pajak" title.
        review.type = .stnk
        #expect(review.checkedFields.last?.title == "review.taxValidUntil")
    }
}
