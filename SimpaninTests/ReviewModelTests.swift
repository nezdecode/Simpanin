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

    @Test func settingTheExpiryClearsItsMark() throws {
        let review = model()
        review.load(Self.sim, pages: [try page()])
        review.setExpiry(CalendarDate(year: 2028, month: 1, day: 4))
        #expect(review.expiry == CalendarDate(year: 2028, month: 1, day: 4))
        #expect(!review.expiryNeedsCheck)
    }

    @Test func typedChangesAreNoticed() throws {
        let review = model()
        review.load(Self.ktp, pages: [try page()])
        #expect(!review.hasTypedChanges)
        review.setValue("BUDI CONTOH", for: FieldKey.name)
        #expect(review.hasTypedChanges)
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
        #expect(!review.hasTypedChanges)
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
