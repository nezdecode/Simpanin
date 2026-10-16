//
//  SIMParserTests.swift
//  ParsersTests
//
//  Created by Inez Amanda on 15/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Parsers
import Testing
import VaultCore

/// Synthetic cards only: NIKs start with 00, a province no real region has, and old SIM numbers
/// are all zeros but the last digits.
@Suite("SIM parser")
struct SIMParserTests {
    static let today = CalendarDate(year: 2026, month: 10, day: 15)!

    func parse(_ lines: [String]) -> ParsedDocument? {
        SIMParser.parse(lines, today: Self.today)
    }

    /// The older card: the number with dashes under the class, fields numbered without labels, and
    /// the expiry alone at the bottom.
    static func oldCard(
        classLine: String = "C", number: String = "0000-0000-000001", name: String = "BUDI CONTOH",
        birth: String = "JAKARTA, 17-08-1990", expiry: String = "04-01-2027"
    ) -> [String] {
        [
            "INDONESIA", "SURAT IZIN MENGEMUDI", "DRIVING LICENSE", classLine, number, "1. \(name)", "2. \(birth)",
            "3. O - PRIA", "4. JL. CONTOH NO. 1", "KOTA CONTOH", "5. KARYAWAN", "6. METRO", expiry,
        ]
    }

    /// The card from July 2024: bilingual labels above their values, the NIK as the number, and the
    /// expiry under the QR code. Dates as real cards print them.
    static func newCard(
        classLine: String = "A", number: String = "0012341708900001", name: String = "BUDI CONTOH",
        birth: String = "JAKARTA, 17-08-1990", sex: String = "PRIA", expiry: String = "29-07-2029"
    ) -> [String] {
        [
            "INDONESIA", "DRIVING LICENSE", "SURAT IZIN MENGEMUDI", number, classLine, "Mobil Penumpang Pribadi/",
            "Passenger Car/ Personal Goods", "Nama/Name", name, "Tempat, Tgl Lahir/Place, Date of Birth", birth,
            "Gol Darah/Blood Type", "Jenis Kelamin/Sex", "O", sex, "Alamat/Address", "JL. CONTOH NO. 1",
            "Pekerjaan/Occupation", "KARYAWAN", "Diterbitkan Oleh/Issued by", "POLRES CONTOH", expiry,
        ]
    }

    @Test func aCleanOldCard() throws {
        let result = try #require(parse(Self.oldCard()))
        #expect(result.type == .simC)
        #expect(result.fields.values[FieldKey.simNumber] == "0000-0000-000001")
        #expect(result.fields.values[FieldKey.name] == "BUDI CONTOH")
        #expect(result.fields.values[FieldKey.birthDate] == "1990-08-17")
        #expect(result.expiry == CalendarDate(year: 2027, month: 1, day: 4))
        #expect(result.needsCheck.isEmpty)
        #expect(!result.typeNeedsCheck)
        #expect(!result.expiryNeedsCheck)
    }

    @Test func aCleanNewCard() throws {
        let result = try #require(parse(Self.newCard()))
        #expect(result.type == .simA)
        #expect(result.fields.values[FieldKey.simNumber] == "0012341708900001")
        #expect(result.fields.values[FieldKey.name] == "BUDI CONTOH")
        #expect(result.fields.values[FieldKey.birthDate] == "1990-08-17")
        #expect(result.expiry == CalendarDate(year: 2029, month: 7, day: 29))
        #expect(result.needsCheck.isEmpty)
        #expect(!result.typeNeedsCheck)
        #expect(!result.expiryNeedsCheck)
    }

    @Test func birthDatesWithAMonthNameOrNumbers() throws {
        for birth in ["JAKARTA, 17 AGUSTUS 1990", "JAKARTA, 17 AUGUST 1990", "JAKARTA, 17-08-1990"] {
            let result = try #require(parse(Self.newCard(birth: birth)))
            #expect(result.fields.values[FieldKey.birthDate] == "1990-08-17", "\(birth)")
            #expect(result.needsCheck.isEmpty, "\(birth)")
        }
    }

    @Test func expiryWithAnySeparator() throws {
        for expiry in ["29-07-2029", "29/07/2029", "29.07.2029"] {
            let result = try #require(parse(Self.newCard(expiry: expiry)))
            #expect(result.expiry == CalendarDate(year: 2029, month: 7, day: 29), "\(expiry)")
            #expect(!result.expiryNeedsCheck, "\(expiry)")
        }
    }

    @Test func everyClass() throws {
        let classes: [(String, DocumentType)] = [
            ("A", .simA), ("BI", .simB1), ("BII", .simB2), ("C", .simC), ("CI", .simC1), ("CII", .simC2),
            ("D", .simD), ("DI", .simD1), ("A UMUM", .simAUmum), ("BI UMUM", .simB1Umum),
            ("BII UMUM", .simB2Umum),
        ]
        for (line, type) in classes {
            let result = try #require(parse(Self.oldCard(classLine: line)))
            #expect(result.type == type, "\(line)")
            #expect(!result.typeNeedsCheck, "\(line)")
        }
    }

    /// A 1 read for an I is a likely misread, but still a guess, so the class is marked.
    @Test func aMisreadClassIsReadAndMarked() throws {
        for (line, type) in [("B1", DocumentType.simB1), ("B11", .simB2), ("C l", .simC1)] {
            let result = try #require(parse(Self.oldCard(classLine: line)))
            #expect(result.type == type, "\(line)")
            #expect(result.typeNeedsCheck, "\(line)")
        }
    }

    /// The user picks the class on the review screen.
    @Test func noReadableClassIsAClasslessSIMAndMarked() throws {
        let result = try #require(parse(Self.oldCard(classLine: "X")))
        #expect(result.type == .sim)
        #expect(result.typeNeedsCheck)
    }

    /// On a new card the blood type is a line of its own, and blood type A looks like class A.
    @Test func aBloodTypeIsNeverTakenForTheClass() throws {
        var lines = Self.newCard(classLine: "C")
        let blood = try #require(lines.firstIndex(of: "O"))
        lines[blood] = "A"
        let result = try #require(parse(lines))
        #expect(result.type == .simC)
        #expect(!result.typeNeedsCheck)
    }

    /// Without a readable first field, a blood type could be the only class-like line, so it's marked.
    @Test func withNoFieldReadTheClassIsMarked() throws {
        var lines = Self.newCard(classLine: "")
        let nameLabel = try #require(lines.firstIndex(of: "Nama/Name"))
        lines[nameLabel] = "Nana/Nane"
        let blood = try #require(lines.firstIndex(of: "O"))
        lines[blood] = "A"
        let result = try #require(parse(lines))
        #expect(result.typeNeedsCheck)
    }

    /// On a card with labels only the name label starts the fields, so an address line like "1, RT 001"
    /// can't stand in for it and let a blood type through as the class.
    @Test func onALabelledCardOnlyTheNameLabelStartsTheFields() throws {
        var lines = Self.newCard(classLine: "X")
        let nameLabel = try #require(lines.firstIndex(of: "Nama/Name"))
        lines[nameLabel] = "Nana/Nane"
        let address = try #require(lines.firstIndex(of: "JL. CONTOH NO. 1"))
        lines[address] = "1, RT 001/002"
        let blood = try #require(lines.firstIndex(of: "O"))
        lines[blood] = "A"
        #expect(try #require(parse(lines)).typeNeedsCheck)
    }

    // MARK: The number

    /// On a new card the number is a NIK, so it's checked like one.
    @Test func aNewNumberIsCheckedAgainstTheBirthDateAndSex() throws {
        let wrongDate = try #require(parse(Self.newCard(birth: "JAKARTA, 18-08-1990")))
        #expect(wrongDate.needsCheck == [FieldKey.simNumber, FieldKey.birthDate])
        let woman = try #require(parse(Self.newCard(number: "0012345708900002", sex: "WANITA")))
        #expect(woman.needsCheck.isEmpty)
        let manWithAWomansDay = try #require(parse(Self.newCard(number: "0012345708900002", sex: "PRIA")))
        #expect(manWithAWomansDay.needsCheck == [FieldKey.simNumber])
        let womanWithAMansDay = try #require(parse(Self.newCard(sex: "WANITA")))
        #expect(womanWithAMansDay.needsCheck == [FieldKey.simNumber])
    }

    /// The sex is read from its own field, so a word in the address doesn't hide a mismatch.
    @Test func theSexIsReadOnlyFromItsField() throws {
        var lines = Self.newCard(sex: "WANITA")
        let address = try #require(lines.firstIndex(of: "JL. CONTOH NO. 1"))
        lines[address] = "JL. PRIA SEJATI NO. 1"
        #expect(try #require(parse(lines)).needsCheck == [FieldKey.simNumber])
    }

    /// Recognition may join the label and its value on one line.
    @Test func theSexOnTheLabelLineIsRead() throws {
        var lines = Self.newCard()
        let label = try #require(lines.firstIndex(of: "Jenis Kelamin/Sex"))
        lines[label] = "Jenis Kelamin/Sex : WANITA"
        lines.remove(at: label + 2)
        #expect(try #require(parse(lines)).needsCheck == [FieldKey.simNumber])
    }

    /// An old number isn't a NIK, so there's nothing to compare it with.
    @Test func anOldNumberIsntCheckedLikeANIK() throws {
        let result = try #require(parse(Self.oldCard(number: "0000-0000-000002", birth: "JAKARTA, 01-12-1985")))
        #expect(result.needsCheck.isEmpty)
    }

    /// The layout says which number to expect: a NIK on a card with labels, 14 digits on a numbered one.
    @Test func aNumberThatDoesntFitTheLayoutIsMarked() throws {
        let newCardOldNumber = try #require(parse(Self.newCard(number: "00123417089000")))
        #expect(newCardOldNumber.needsCheck.contains(FieldKey.simNumber))
        let oldCardNewNumber = try #require(parse(Self.oldCard(number: "0012341708900001")))
        #expect(oldCardNewNumber.needsCheck.contains(FieldKey.simNumber))
    }

    /// When the layout can't be told, the number's length alone isn't a reason to mark it.
    @Test func anUnknownLayoutDoesntMarkTheNumbersLength() throws {
        let neither = ["SURAT IZIN MENGEMUDI", "A", "0000-0000-000001", "BUDI CONTOH", "04-01-2027"]
        #expect(try #require(parse(neither)).needsCheck.contains(FieldKey.simNumber) == false)
        var both = Self.oldCard()
        both.insert("Nama/Name", at: 5)
        #expect(try #require(parse(both)).needsCheck.contains(FieldKey.simNumber) == false)
    }

    @Test func lookalikeLettersInTheNumberAreCorrectedAndMarked() throws {
        let result = try #require(parse(Self.oldCard(number: "OOOO-0000-00000I")))
        #expect(result.fields.values[FieldKey.simNumber] == "0000-0000-000001")
        #expect(result.needsCheck == [FieldKey.simNumber])
    }

    @Test func aNumberOfTheWrongLengthIsMarked() throws {
        let result = try #require(parse(Self.oldCard(number: "0000-0000-0001")))
        #expect(result.needsCheck.contains(FieldKey.simNumber))
    }

    // MARK: Name and birth date

    @Test func aNameThatWrapsIsMarked() throws {
        var lines = Self.oldCard()
        lines.insert("SANTOSO", at: 6)
        let result = try #require(parse(lines))
        #expect(result.fields.values[FieldKey.name] == "BUDI CONTOH")
        #expect(result.needsCheck == [FieldKey.name])
    }

    @Test func aNameThatWrapsOnANewCardIsMarked() throws {
        var lines = Self.newCard()
        let name = try #require(lines.firstIndex(of: "BUDI CONTOH"))
        lines.insert("SANTOSO", at: name + 1)
        let result = try #require(parse(lines))
        #expect(result.fields.values[FieldKey.name] == "BUDI CONTOH")
        #expect(result.needsCheck == [FieldKey.name])
    }

    @Test func aMisreadNameIsMarked() throws {
        for name in ["BUDI C0NTOH", "BUDl CONTOH", ", BUDI CONTOH"] {
            let result = try #require(parse(Self.newCard(name: name)))
            #expect(result.needsCheck == [FieldKey.name], "\(name)")
        }
    }

    /// A corrected birth date is a guess, unless a new card's number, the NIK, confirms it.
    @Test func aBirthDateWithALookalikeDigit() throws {
        let newCard = try #require(parse(Self.newCard(birth: "JAKARTA, l7-08-1990")))
        #expect(newCard.fields.values[FieldKey.birthDate] == "1990-08-17")
        #expect(newCard.needsCheck.isEmpty)
        let oldCard = try #require(parse(Self.oldCard(birth: "JAKARTA, l7-08-1990")))
        #expect(oldCard.fields.values[FieldKey.birthDate] == "1990-08-17")
        #expect(oldCard.needsCheck.contains(FieldKey.birthDate))
    }

    @Test func aBirthDateThatCantBeRightIsMarked() throws {
        for birth in ["JAKARTA, 17-08-1090", "JAKARTA, 17-08-2090", "JAKARTA, 31-02-1990"] {
            let result = try #require(parse(Self.oldCard(birth: birth)))
            #expect(result.needsCheck.contains(FieldKey.birthDate), "\(birth)")
        }
    }

    // MARK: Expiry

    /// The expiry has no label, so it's the one date that isn't the birth date.
    @Test func twoCandidateExpiryDatesAreMarked() throws {
        var lines = Self.oldCard()
        lines.append("05-01-2027")
        let result = try #require(parse(lines))
        #expect(result.expiry == nil)
        #expect(result.expiryNeedsCheck)
    }

    @Test func aMissingExpiryIsMarked() throws {
        let result = try #require(parse(Self.oldCard(expiry: "")))
        #expect(result.expiry == nil)
        #expect(result.expiryNeedsCheck)
    }

    /// With the birth line misread, its date is the only one left; it must not pass as the expiry.
    @Test func aBirthDateIsNeverTakenForTheExpiry() throws {
        var lines = Self.oldCard(expiry: "")
        let birth = try #require(lines.firstIndex(of: "2. JAKARTA, 17-08-1990"))
        lines[birth] = "Z. JAKARTA, 17-08-1990"
        let result = try #require(parse(lines))
        #expect(result.expiryNeedsCheck)
    }

    /// A SIM needs its holder to be at least 17, so an expiry earlier than that is a misread.
    @Test func anExpiryTooSoonAfterTheBirthDateIsMarked() throws {
        let result = try #require(parse(Self.oldCard(expiry: "04-01-2005")))
        #expect(result.expiryNeedsCheck)
    }

    /// A SIM is valid for five years, so an expiry further out is a misread.
    @Test func anExpiryTooFarAheadIsMarked() throws {
        let result = try #require(parse(Self.oldCard(expiry: "04-01-2037")))
        #expect(result.expiryNeedsCheck)
    }

    /// An expired SIM is still a SIM, and its expiry is read as it is.
    @Test func anExpiredSIMIsReadUnmarked() throws {
        let result = try #require(parse(Self.oldCard(expiry: "04-01-2020")))
        #expect(result.expiry == CalendarDate(year: 2020, month: 1, day: 4))
        #expect(!result.expiryNeedsCheck)
    }

    /// Regex digits include full-width and other scripts, which Int can't read; a scan must never crash.
    @Test func digitsFromOtherScriptsNeverCrash() throws {
        let birth = "JAKARTA, \u{FF11}\u{FF17}-08-1990"
        let sim = try #require(parse(Self.oldCard(birth: birth, expiry: "\u{FF10}\u{FF14}-01-2027")))
        #expect(sim.needsCheck.contains(FieldKey.birthDate))
        #expect(sim.expiryNeedsCheck)
        let ktp = try #require(
            KTPParser.parse(["NIK : 0012341708900001", "Tempat/Tgl Lahir : \(birth)"], today: Self.today))
        #expect(ktp.needsCheck.contains(FieldKey.birthDate))
    }

    /// One full-width digit beside an ASCII one must not leave a shorter, wrong date behind.
    @Test func aDayWithOneDigitFromAnotherScriptIsMarkedNotShortened() throws {
        for birth in ["JAKARTA, \u{FF12}5 AGUSTUS 1990", "JAKARTA, \u{FF12}5-08-1990"] {
            let result = try #require(parse(Self.oldCard(birth: birth)))
            #expect(result.fields.values[FieldKey.birthDate] == nil, "\(birth)")
            #expect(result.needsCheck.contains(FieldKey.birthDate), "\(birth)")
        }
    }

    @Test func notASIM() {
        #expect(parse(["PROVINSI DKI JAKARTA", "NIK : 0012341708900001", "Nama : BUDI CONTOH"]) == nil)
        #expect(parse([]) == nil)
        #expect(KTPParser.parse(Self.newCard(), today: Self.today) == nil)
        #expect(KTPParser.parse(Self.oldCard(), today: Self.today) == nil)
    }
}
