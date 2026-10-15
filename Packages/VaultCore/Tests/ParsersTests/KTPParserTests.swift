//
//  KTPParserTests.swift
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

/// Synthetic cards only: every NIK starts with 00, a province no real region has.
@Suite("KTP parser")
struct KTPParserTests {
    /// A clean KTP as text recognition returns it, one line per printed line.
    static func card(
        nik: String = "0012341708900001", name: String = "BUDI CONTOH",
        birth: String = "JAKARTA, 17-08-1990", sex: String = "LAKI-LAKI"
    ) -> [String] {
        [
            "PROVINSI DKI JAKARTA", "KOTA JAKARTA SELATAN", "NIK : \(nik)", "Nama : \(name)",
            "Tempat/Tgl Lahir : \(birth)", "Jenis Kelamin : \(sex)   Gol. Darah : O", "Alamat : JL. CONTOH NO. 1",
            "Agama : ISLAM", "Kewarganegaraan : WNI", "Berlaku Hingga : SEUMUR HIDUP",
        ]
    }

    @Test func aCleanCard() throws {
        let result = try #require(KTPParser.parse(Self.card()))
        #expect(result.type == .ktp)
        #expect(result.fields.values[KTPParser.nik] == "0012341708900001")
        #expect(result.fields.values[KTPParser.name] == "BUDI CONTOH")
        #expect(result.fields.values[KTPParser.birthDate] == "1990-08-17")
        #expect(result.expiry == nil)  // a KTP is valid for life
        #expect(result.needsCheck.isEmpty)
    }

    @Test func spacesInsideTheNIKAreDropped() throws {
        let result = try #require(KTPParser.parse(Self.card(nik: "0012 3417 0890 0001")))
        #expect(result.fields.values[KTPParser.nik] == "0012341708900001")
        #expect(result.needsCheck.isEmpty)
    }

    /// Letters that look like digits are corrected, but a correction is a guess, so it's marked.
    @Test func lookalikeLettersInTheNIKAreCorrectedAndMarked() throws {
        let result = try #require(KTPParser.parse(Self.card(nik: "OO12341708SOOOOI")))
        #expect(result.fields.values[KTPParser.nik] == "0012341708500001")
        #expect(result.needsCheck.contains(KTPParser.nik))
    }

    @Test func labelAndValueOnSeparateLines() throws {
        let lines = [
            "PROVINSI DKI JAKARTA", "NIK", ": 0012341708900001", "Nama", ": BUDI CONTOH", "Tempat/Tgl Lahir",
            ": JAKARTA, 17-08-1990", "Jenis Kelamin", ": LAKI-LAKI",
        ]
        let result = try #require(KTPParser.parse(lines))
        #expect(result.fields.values[KTPParser.nik] == "0012341708900001")
        #expect(result.fields.values[KTPParser.name] == "BUDI CONTOH")
        #expect(result.fields.values[KTPParser.birthDate] == "1990-08-17")
        // Which line belongs to a label is a guess here, so every value is marked.
        #expect(result.needsCheck == [KTPParser.nik, KTPParser.name, KTPParser.birthDate])
    }

    /// Recognition drops the colon or reads it as a semicolon.
    @Test func labelsWithoutAColon() throws {
        for separator in ["", " ;", ";"] {
            let lines = [
                "NIK\(separator) 0012341708900001", "Nama\(separator) BUDI CONTOH",
                "Tempat/Tgl. Lahir\(separator) JAKARTA, 17-08-1990",
            ]
            let result = try #require(KTPParser.parse(lines), "\(separator)")
            #expect(result.fields.values[KTPParser.nik] == "0012341708900001", "\(separator)")
            #expect(result.fields.values[KTPParser.name] == "BUDI CONTOH", "\(separator)")
            #expect(result.fields.values[KTPParser.birthDate] == "1990-08-17", "\(separator)")
            #expect(result.needsCheck.isEmpty, "\(separator)")
        }
    }

    /// Recognition can return the label column before the value column. A label is never taken as a
    /// value, and the card is still a KTP, with everything marked.
    @Test func labelsBeforeValuesNeverTakeALabelAsAValue() throws {
        let lines = [
            "PROVINSI DKI JAKARTA", "NIK", "Nama", "Tempat/Tgl Lahir", ": 0012341708900001", ": BUDI CONTOH",
            ": JAKARTA, 17-08-1990",
        ]
        let result = try #require(KTPParser.parse(lines))
        #expect(result.fields.values[KTPParser.name] == nil)
        #expect(result.fields.values[KTPParser.nik] == nil)
        #expect(result.needsCheck == [KTPParser.nik, KTPParser.name, KTPParser.birthDate])
    }

    /// A long name wraps onto the next line; only its first part is read, so it's marked.
    @Test func aNameThatWrapsIsMarked() throws {
        let lines = [
            "NIK : 0012341708900001", "Nama : BUDI CONTOH", "SANTOSO", "Tempat/Tgl Lahir : JAKARTA, 17-08-1990",
        ]
        let result = try #require(KTPParser.parse(lines))
        #expect(result.needsCheck == [KTPParser.name])
    }

    /// Women's NIKs carry the day of birth plus 40.
    @Test func aWomansNIKMatchesHerBirthDate() throws {
        let result = try #require(
            KTPParser.parse(Self.card(nik: "0012345708900002", name: "SITI CONTOH", sex: "PEREMPUAN")))
        #expect(result.needsCheck.isEmpty)
    }

    @Test func aNIKThatDoesntMatchTheBirthDateIsMarked() throws {
        let result = try #require(KTPParser.parse(Self.card(birth: "JAKARTA, 18-08-1990")))
        #expect(result.needsCheck == [KTPParser.nik, KTPParser.birthDate])
    }

    @Test func aDigitInTheNameIsMarkedNotChanged() throws {
        let result = try #require(KTPParser.parse(Self.card(name: "BUDI C0NTOH")))
        #expect(result.fields.values[KTPParser.name] == "BUDI C0NTOH")
        #expect(result.needsCheck == [KTPParser.name])
    }

    @Test func otherSeparatorsInTheBirthDate() throws {
        for birth in ["JAKARTA, 17.08.1990", "JAKARTA, 17/08/1990", "JAKARTA,17-08-1990"] {
            let result = try #require(KTPParser.parse(Self.card(birth: birth)))
            #expect(result.fields.values[KTPParser.birthDate] == "1990-08-17", "\(birth)")
            #expect(result.needsCheck.isEmpty, "\(birth)")
        }
    }

    /// Stored like every date in the vault. A date that can't exist is left empty for the user.
    @Test func anImpossibleBirthDateIsMarkedAndLeftEmpty() throws {
        let result = try #require(KTPParser.parse(Self.card(birth: "JAKARTA, 31-02-1990")))
        #expect(result.fields.values[KTPParser.birthDate] == nil)
        #expect(result.needsCheck.contains(KTPParser.birthDate))
    }

    @Test func aNIKThatIsntSixteenDigitsIsMarked() throws {
        let result = try #require(KTPParser.parse(Self.card(nik: "00123417089000")))
        #expect(result.needsCheck.contains(KTPParser.nik))
    }

    @Test func missingLinesAreMarked() throws {
        let result = try #require(KTPParser.parse(["PROVINSI DKI JAKARTA", "NIK : 0012341708900001"]))
        #expect(result.fields.values[KTPParser.nik] == "0012341708900001")
        #expect(result.needsCheck == [KTPParser.name, KTPParser.birthDate])
    }

    @Test func notAKTP() {
        #expect(KTPParser.parse(["REPUBLIK INDONESIA", "PASPOR", "P<IDNCONTOH<<BUDI"]) == nil)
        #expect(KTPParser.parse([]) == nil)
    }
}
