//
//  ScanPagesTests.swift
//  ParsersTests
//
//  Created by Inez Amanda on 26/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Parsers
import Testing
import VaultCore

/// Synthetic pages only: NIKs start with 00, and old SIM numbers are zeros but the last digits.
@Suite("Scan pages")
struct ScanPagesTests {
    static let nik = "0012341708900001"
    static let otherNIK = "0012341708900002"
    static let oldNumber = "00000000000001"

    static func ktp(_ nik: String? = ScanPagesTests.nik, nikReasons: Set<CheckReason> = []) -> ParsedDocument {
        var fields = [FieldKey.name: "BUDI CONTOH"]
        fields[FieldKey.nik] = nik
        return ParsedDocument(
            type: .ktp, fields: DocumentFields(fields), expiry: nil,
            reasons: nikReasons.isEmpty ? [:] : [FieldKey.nik: nikReasons])
    }

    static func sim(
        _ type: DocumentType = .simA, number: String? = ScanPagesTests.nik, numberReasons: Set<CheckReason> = [],
        typeReasons: Set<CheckReason> = []
    ) -> ParsedDocument {
        var fields = [FieldKey.name: "BUDI CONTOH"]
        fields[FieldKey.simNumber] = number
        return ParsedDocument(
            type: type, fields: DocumentFields(fields), expiry: nil,
            reasons: numberReasons.isEmpty ? [:] : [FieldKey.simNumber: numberReasons], typeReasons: typeReasons)
    }

    /// A SIM's back: its title, no number.
    static let back = ParsedDocument(type: .sim, fields: DocumentFields([:]), expiry: nil, typeReasons: [.classUnclear])

    func relations(_ pages: [ParsedDocument?]) -> [PageRelation?] {
        ScanPages.read(pages).pages.map { $0?.relation }
    }

    // MARK: The source page

    @Test func theFirstFrontIsTheSource() {
        #expect(ScanPages.read([Self.ktp(), Self.sim()]).source == 0)
    }

    @Test func aBackBeforeTheFrontMakesPage2TheSource() {
        let reading = ScanPages.read([Self.back, Self.sim()])
        #expect(reading.source == 1)
        #expect(reading.pages[0] == nil)
    }

    @Test func noFrontHasNoSourceAndNoRelations() {
        let reading = ScanPages.read([Self.back, nil])
        #expect(reading.source == nil)
        #expect(reading.pages == [nil, nil])
    }

    /// People scan again to get a better read.
    @Test func theSameCardScannedTwiceTakesTheBestReadPage() {
        let blurred = Self.ktp(nikReasons: [.readFromAnotherLine])
        let reading = ScanPages.read([blurred, Self.ktp()])
        #expect(reading.source == 1)
        #expect(reading.pages[0]?.relation == .sameCard)
    }

    @Test func aTieKeepsTheFirstPage() {
        #expect(ScanPages.read([Self.ktp(), Self.ktp()]).source == 0)
    }

    /// Inez, 20 Oct: a misread number isn't the same card, so it can't take over as the source.
    @Test func aMisreadNumberIsntTheSameCardSoTheFirstFrontStays() {
        let misread = Self.ktp("0012341708900007", nikReasons: [.lookalike])
        let reading = ScanPages.read([misread, Self.ktp()])
        #expect(reading.source == 0)
        #expect(reading.pages[1]?.relation == .unsureNumber)
    }

    @Test func aNumberWithoutDigitsIsNeverTheSameCard() {
        #expect(relations([Self.ktp("?"), Self.ktp("?")]) == [.source, .unsureNumber])
    }

    /// What counts as a front is unchanged, so the fields come from the same page as before.
    @Test func aNIKWithoutDigitsIsStillAFront() {
        #expect(ScanPages.read([Self.ktp("?"), Self.ktp()]).source == 0)
    }

    /// The review refuses it, and the parser leaves it unmarked, so its length can't say "another card".
    @Test func aKTPNIKOfTheWrongLengthIsUnsureNotAnotherCard() {
        #expect(relations([Self.ktp(), Self.ktp("001234170890001")]) == [.source, .unsureNumber])
    }

    // MARK: A SIM without its class

    @Test func aSIMWithoutAClassIsGroupedForTheSource() {
        let classless = Self.sim(.sim, typeReasons: [.classUnclear])
        let reading = ScanPages.read([classless, Self.sim(.simA)])
        #expect(reading.source == 1)
    }

    @Test func aSIMWithoutAClassAndTheSameDigitsIsClassUnread() {
        let classless = Self.sim(.sim, typeReasons: [.classUnclear])
        #expect(relations([Self.sim(.simA), classless]) == [.source, .classUnread])
    }

    /// The classed page has more marks elsewhere, so the classless one stays the source.
    @Test func aClasslessSourceAndAClassedPageWithTheSameDigitsHaveNoNote() {
        let classless = Self.sim(.sim, typeReasons: [.classUnclear])
        var classed = Self.sim(.simA)
        classed.reasons = [FieldKey.name: [.oddCharacters], FieldKey.birthDate: [.notFound]]
        #expect(relations([classless, classed]) == [.source, .sameCard])
    }

    @Test func aClasslessPageWithOtherDigitsFollowsTheSameTypeRules() {
        let classless = Self.sim(.sim, number: Self.otherNIK, typeReasons: [.classUnclear])
        #expect(relations([Self.sim(.simA), classless]) == [.source, .otherCard])
    }

    /// The group only picks the source; each page is then taken against that source.
    @Test func relationsAreTakenAgainstTheChosenSource() {
        let classless = Self.sim(.sim, typeReasons: [.classUnclear])
        let reading = ScanPages.read([classless, Self.sim(.simA), Self.sim(.simB1)])
        #expect(reading.source == 1)
        #expect(reading.pages.map { $0?.relation } == [.classUnread, .source, .otherType])
    }

    // MARK: The same type

    @Test func sameTypeOtherCleanNumberIsOtherCard() {
        #expect(relations([Self.ktp(), Self.ktp(Self.otherNIK)]) == [.source, .otherCard])
    }

    @Test func sameTypeOtherNumberWithAMarkIsUnsureNumber() {
        let marked = Self.ktp(Self.otherNIK, nikReasons: [.readFromAnotherLine])
        #expect(relations([Self.ktp(), marked]) == [.source, .unsureNumber])
        #expect(relations([Self.ktp(nikReasons: [.lookalike]), Self.ktp(Self.otherNIK)]) == [.source, .unsureNumber])
    }

    /// 14 digits against 16 can't be a misread: an old card and its renewal.
    @Test func oldAndNewSIMNumbersAreOtherCards() {
        let old = Self.sim(.simA, number: Self.oldNumber, numberReasons: [.severalNumbers])
        #expect(relations([Self.sim(.simA), old]) == [.source, .otherCard])
    }

    @Test func aMixedLayoutPageIsNeverAnotherCardByLength() {
        let mixed = Self.sim(.simA, number: Self.oldNumber, numberReasons: [.mixedLayout], typeReasons: [.mixedLayout])
        #expect(relations([Self.sim(.simA), mixed]) == [.source, .unsureNumber])
    }

    // MARK: Another type

    @Test func anotherTypeIsOtherType() {
        #expect(relations([Self.ktp(), Self.sim(.simA, number: Self.otherNIK)]) == [.source, .otherType])
    }

    /// A new SIM's number is its holder's NIK; they're still two documents.
    @Test func aKTPAndANewSIMWithTheSameDigitsAreOtherTypes() {
        #expect(relations([Self.ktp(), Self.sim(.simA)]) == [.source, .otherType])
    }

    @Test func twoSIMClassesAreOtherTypes() {
        #expect(relations([Self.sim(.simA), Self.sim(.simC)]) == [.source, .otherType])
    }

    // MARK: Pages and values

    @Test func digitsAreComparedWithoutDashes() {
        let dashed = Self.sim(.simA, number: "0000-0000-000001")
        #expect(relations([Self.sim(.simA, number: Self.oldNumber), dashed]) == [.source, .sameCard])
    }

    @Test func aBackOrAnUnreadPageHasNoRelation() {
        #expect(relations([Self.ktp(), Self.back, nil]) == [.source, nil, nil])
    }

    /// A page can be another person's card, so only what it was read as is kept, never a value.
    @Test func pageReadsHoldReasonsOnly() throws {
        let page = Self.sim(.simC, number: Self.otherNIK, numberReasons: [.lookalike], typeReasons: [.lookalike])
        let read = try #require(ScanPages.read([Self.ktp(), page]).pages[1])
        #expect(
            read
                == PageRead(
                    type: .simC, relation: .otherType, reasons: [FieldKey.simNumber: [.lookalike]],
                    typeReasons: [.lookalike]))
    }
}
