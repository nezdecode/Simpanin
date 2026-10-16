//
//  ReviewModelTests.swift
//  SimpaninTests
//
//  Created by Inez Amanda on 16/10/26.
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

/// Synthetic values only; NIKs start with 00.
@MainActor
@Suite("Review model")
struct ReviewModelTests {
    func page() throws -> CGImage {
        let context = try #require(
            CGContext(
                data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 8,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        return try #require(context.makeImage())
    }

    static let ktp = ParsedDocument(
        type: .ktp,
        fields: DocumentFields([
            FieldKey.nik: "0012341708900001", FieldKey.name: "BUDI C0NTOH", FieldKey.birthDate: "1990-08-17",
        ]),
        expiry: nil, needsCheck: [FieldKey.name])

    static let sim = ParsedDocument(
        type: .simC,
        fields: DocumentFields([FieldKey.simNumber: "0000-0000-000001", FieldKey.name: "BUDI CONTOH"]),
        expiry: CalendarDate(year: 2027, month: 1, day: 4), needsCheck: [], expiryNeedsCheck: true)

    func model(
        _ store: FakeDocuments = FakeDocuments(), encode: @escaping @Sendable (CGImage) -> Data? = { _ in Data([1]) }
    )
        -> ReviewModel
    {
        ReviewModel(store: store, encode: encode)
    }

    @Test func aKTPScanFillsTheForm() throws {
        let review = model()
        review.load(Self.ktp, pages: [try page(), try page()])
        #expect(review.type == .ktp)
        #expect(review.pages.count == 2)
        #expect(review.fieldKeys == [FieldKey.nik, FieldKey.name, FieldKey.birthDate])
        #expect(review.values[FieldKey.nik] == "0012341708900001")
        #expect(review.marked == [FieldKey.name])
        #expect(!review.hasExpiry)
    }

    @Test func aSIMShowsItsNumberAndExpiry() throws {
        let review = model()
        review.load(Self.sim, pages: [try page()])
        #expect(review.fieldKeys == [FieldKey.simNumber, FieldKey.name, FieldKey.birthDate])
        #expect(review.hasExpiry)
        #expect(review.expiry == CalendarDate(year: 2027, month: 1, day: 4))
        #expect(review.expiryNeedsCheck)
    }

    /// Text the parsers don't know: the user picks the type.
    @Test func anUnknownScanAsksForTheType() throws {
        let review = model()
        review.load(nil, pages: [try page()])
        #expect(review.type == .other)
        #expect(review.typeNeedsCheck)
        #expect(review.fieldKeys.isEmpty)
    }

    /// The user checked it, so the mark goes.
    @Test func editingAFieldClearsItsMark() throws {
        let review = model()
        review.load(Self.ktp, pages: [try page()])
        review.setValue("BUDI CONTOH", for: FieldKey.name)
        #expect(review.values[FieldKey.name] == "BUDI CONTOH")
        #expect(review.marked.isEmpty)
    }

    /// An expiry that wasn't read shows as missing, never as today, and can still be saved empty.
    @Test func aMissingExpiryIsShownAsMissing() async throws {
        let store = FakeDocuments()
        let review = model(store)
        review.load(Self.ktp, pages: [try page()])
        #expect(!review.expiryMissing)
        review.type = .simC
        #expect(review.expiryMissing)
        review.setExpiry(CalendarDate(year: 2029, month: 1, day: 4))
        #expect(!review.expiryMissing)
        review.setExpiry(nil)
        #expect(await review.save())
        #expect(try await store.documents().first?.expiry == nil)
    }

    /// The expiry picker shows UTC, so a calendar day survives the trip there and back unchanged.
    @Test func anExpiryRoundTripsThroughThePicker() throws {
        let day = try #require(CalendarDate(year: 2029, month: 1, day: 4))
        #expect(CalendarDate(utc: try #require(day.utcDate)) == day)
    }

    @Test func settingTheExpiryClearsItsMark() throws {
        let review = model()
        review.load(Self.sim, pages: [try page()])
        review.setExpiry(CalendarDate(year: 2028, month: 1, day: 4))
        #expect(review.expiry == CalendarDate(year: 2028, month: 1, day: 4))
        #expect(!review.expiryNeedsCheck)
    }

    /// An expired SIM is real, not a misread: its expiry isn't marked for having passed.
    @Test func anExpiredSIMIsNotMarked() throws {
        let review = model()
        let expired = ParsedDocument(
            type: .simC, fields: DocumentFields([:]), expiry: CalendarDate(year: 2001, month: 1, day: 4), needsCheck: []
        )
        review.load(expired, pages: [try page()])
        #expect(!review.expiryNeedsCheck)
        #expect(!review.expiryMissing)
    }

    @Test func typedChangesAreNoticed() throws {
        let review = model()
        review.load(Self.ktp, pages: [try page()])
        #expect(!review.hasUserChanges)
        review.setValue("BUDI CONTOH", for: FieldKey.name)
        #expect(review.hasUserChanges)
    }

    /// A type the user picked is their decision, no longer the parser's guess.
    @Test func pickingATypeClearsItsMark() throws {
        let review = model()
        review.load(nil, pages: [try page()])
        #expect(review.typeNeedsCheck)
        review.type = .ktp
        #expect(!review.typeNeedsCheck)
    }

    /// A type, a SIM class or a date picked by hand is the user's choice too, and a rescan would undo it.
    @Test func choicesAreChangesToo() throws {
        let review = model()
        review.load(Self.sim, pages: [try page()])
        review.type = .simA
        #expect(review.hasUserChanges)
        review.type = .simC
        #expect(!review.hasUserChanges)
        review.setExpiry(CalendarDate(year: 2031, month: 5, day: 2))
        #expect(review.hasUserChanges)
    }

    /// A rescan may be a different card: every field comes from it, none from before.
    @Test func aRescanReplacesEveryField() throws {
        let review = model()
        review.load(Self.ktp, pages: [try page()])
        review.setValue("TYPED", for: FieldKey.name)
        review.label = "Ibu"
        review.load(Self.sim, pages: [try page()])
        #expect(review.type == .simC)
        #expect(review.values[FieldKey.name] == "BUDI CONTOH")
        #expect(review.values[FieldKey.nik] == nil)
        #expect(!review.hasUserChanges)
        #expect(review.label == "Ibu")
    }

    @Test func aLabelThatLooksLikeANumberIsFlagged() {
        let review = model()
        for (label, flagged) in [("Ibu", false), ("KTP 12", false), ("3171 0890", true), ("0012341708900001", true)] {
            review.label = label
            #expect(review.labelLooksLikeANumber == flagged, "\(label)")
        }
    }

    @Test func savingSealsTheChosenTypesFieldsAndPages() async throws {
        let store = FakeDocuments()
        let review = model(store)
        review.load(Self.ktp, pages: [try page(), try page()])
        review.label = "  Ibu  "
        #expect(await review.save())
        let saved = try #require(try await store.documents().first)
        #expect(saved.type == .ktp)
        #expect(saved.label == "Ibu")
        #expect(saved.expiry == nil)
        #expect(await store.created.first?.values == Self.ktp.fields.values)
        #expect(await store.createdPages.first?.count == 2)
    }

    /// Only the shown type's fields are saved: switching a KTP scan to Lainnya saves no NIK.
    @Test func switchingTheTypeSavesOnlyItsFields() async throws {
        let store = FakeDocuments()
        let review = model(store)
        review.load(Self.ktp, pages: [try page()])
        review.type = .other
        review.label = ""
        #expect(await review.save())
        #expect(await store.created.first?.values.isEmpty == true)
        #expect(try await store.documents().first?.label == nil)
    }

    /// Dates show as on the card, day first, and are stored as YYYY-MM-DD like every date in the vault.
    @Test func aBirthDateShowsDayFirst() throws {
        let review = model()
        review.load(Self.ktp, pages: [try page()])
        #expect(review.values[FieldKey.birthDate] == "17-08-1990")
    }

    @Test func aTypedBirthDateIsStoredYearFirst() async throws {
        let store = FakeDocuments()
        let review = model(store)
        review.load(Self.ktp, pages: [try page()])
        review.setValue("01-12-1985", for: FieldKey.birthDate)
        #expect(await review.save())
        #expect(await store.created.first?.values[FieldKey.birthDate] == "1985-12-01")
    }

    /// A date that can't exist is never stored: nothing is saved and the field is marked.
    @Test func anImpossibleBirthDateIsntSaved() async throws {
        let store = FakeDocuments()
        let review = model(store)
        review.load(Self.ktp, pages: [try page()])
        review.setValue("31-02-1990", for: FieldKey.birthDate)
        #expect(await !review.save())
        #expect(review.marked.contains(FieldKey.birthDate))
        #expect(review.problems[FieldKey.birthDate] == .notADate)
        #expect(await store.created.isEmpty)
    }

    /// One save at a time: a second tap while the first is being written is refused, never a duplicate.
    @Test func aSecondSaveWhileOneRunsIsRefused() async throws {
        let store = FakeDocuments()
        await store.gateNextCreate()
        let review = model(store)
        review.load(Self.ktp, pages: [try page()])
        let first = Task { await review.save() }
        try #require(await store.waitUntilCreating())
        #expect(await !review.save())
        await store.releaseCreate()
        #expect(await first.value)
        #expect(await store.created.count == 1)
    }

    /// The scan counts as ended the moment the vault has it, before anything else can run, so a lock
    /// right after never reports a saved scan as dropped.
    @Test func savedIsReportedOnlyWhenTheVaultHasIt() async throws {
        let review = model()
        review.load(Self.ktp, pages: [try page()])
        var reported = 0
        #expect(await review.save(onSaved: { reported += 1 }))
        #expect(reported == 1)
        let failing = FakeDocuments()
        await failing.setFailure(.storageFull)
        let other = model(failing)
        other.load(Self.ktp, pages: [try page()])
        #expect(await !other.save(onSaved: { reported += 1 }))
        #expect(reported == 1)
    }

    @Test func aFullDiskSaysSo() async throws {
        let store = FakeDocuments()
        await store.setFailure(.storageFull)
        let review = model(store)
        review.load(Self.ktp, pages: [try page()])
        #expect(await !review.save())
        #expect(review.saveError == .storageFullOnSave)
    }

    /// A page that can't be prepared is never left out: nothing is saved.
    @Test func aPageThatCantBeEncodedSavesNothing() async throws {
        let store = FakeDocuments()
        let review = model(store, encode: { _ in nil })
        review.load(Self.ktp, pages: [try page()])
        #expect(await !review.save())
        #expect(review.saveError == .saveFailed)
        #expect(await store.created.isEmpty)
    }

    @Test func aRealPageEncodesAsJPEG() throws {
        let data = try #require(PageEncoding.jpeg(try page()))
        #expect(data.prefix(2) == Data([0xFF, 0xD8]))
    }
}

/// Dates as typed, and the NIK checked against the birth date.
extension ReviewModelTests {
    /// A birth date can't be in the future, so Simpan refuses one and says why under the field.
    @Test func aFutureBirthDateIsRefusedWithAReason() async throws {
        let store = FakeDocuments()
        let review = model(store)
        review.load(Self.ktp, pages: [try page()])
        review.setValue("17-08-2999", for: FieldKey.birthDate)
        #expect(review.problems.isEmpty)
        #expect(await !review.save())
        #expect(review.problems[FieldKey.birthDate] == .birthDateInFuture)
        #expect(await store.created.isEmpty)
        review.setValue("17-08-1990", for: FieldKey.birthDate)
        #expect(review.problems.isEmpty)
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
