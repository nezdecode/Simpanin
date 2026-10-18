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
        #expect(result.fields.values[FieldKey.simNumber] == "00000000000001")
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

    @Test func notASIM() {
        #expect(parse(["PROVINSI DKI JAKARTA", "NIK : 0012341708900001", "Nama : BUDI CONTOH"]) == nil)
        #expect(parse([]) == nil)
        #expect(KTPParser.parse(Self.newCard(), today: Self.today) == nil)
        #expect(KTPParser.parse(Self.oldCard(), today: Self.today) == nil)
    }
}
