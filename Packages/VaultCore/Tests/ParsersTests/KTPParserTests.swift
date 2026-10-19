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
    static let today = CalendarDate(year: 2026, month: 10, day: 15)!

    func parse(_ lines: [String]) -> ParsedDocument? {
        KTPParser.parse(lines, today: Self.today)
    }

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
        let result = try #require(parse(Self.card()))
        #expect(result.type == .ktp)
        #expect(result.fields.values[FieldKey.nik] == "0012341708900001")
        #expect(result.fields.values[FieldKey.name] == "BUDI CONTOH")
        #expect(result.fields.values[FieldKey.birthDate] == "1990-08-17")
        #expect(result.expiry == nil)  // a KTP is valid for life
        #expect(result.needsCheck.isEmpty)
    }

    /// Every other card uses August 1990, so this one makes sure month and year come from the NIK.
    @Test func anotherMonthAndYear() throws {
        let result = try #require(parse(Self.card(nik: "0012340112850003", birth: "BANDUNG, 01-12-1985")))
        #expect(result.fields.values[FieldKey.birthDate] == "1985-12-01")
        #expect(result.needsCheck.isEmpty)
    }

    @Test func spacesInsideTheNIKAreDropped() throws {
        let result = try #require(parse(Self.card(nik: "0012 3417 0890 0001")))
        #expect(result.fields.values[FieldKey.nik] == "0012341708900001")
        #expect(result.needsCheck.isEmpty)
    }

    /// Letters that look like digits are corrected, but a correction is a guess, so it's marked.
    @Test func lookalikeLettersInTheNIKAreCorrectedAndMarked() throws {
        let result = try #require(parse(Self.card(nik: "OO12341708SOOOOI")))
        #expect(result.fields.values[FieldKey.nik] == "0012341708500001")
        #expect(result.needsCheck.contains(FieldKey.nik))
    }

    @Test func everyLookalikeLetter() throws {
        let lookalikes: [(String, String)] = [
            ("O", "0"), ("o", "0"), ("D", "0"), ("I", "1"), ("l", "1"), ("|", "1"), ("Z", "2"), ("S", "5"), ("B", "8"),
        ]
        for (letter, digit) in lookalikes {
            let result = try #require(parse(Self.card(nik: "001234170890000" + letter)))
            #expect(result.fields.values[FieldKey.nik] == "001234170890000" + digit, "\(letter)")
        }
    }

    @Test func labelAndValueOnSeparateLines() throws {
        let lines = [
            "PROVINSI DKI JAKARTA", "NIK", ": 0012341708900001", "Nama", ": BUDI CONTOH", "Tempat/Tgl Lahir",
            ": JAKARTA, 17-08-1990", "Jenis Kelamin", ": LAKI-LAKI",
        ]
        let result = try #require(parse(lines))
        #expect(result.fields.values[FieldKey.nik] == "0012341708900001")
        #expect(result.fields.values[FieldKey.name] == "BUDI CONTOH")
        #expect(result.fields.values[FieldKey.birthDate] == "1990-08-17")
        // Which line belongs to a label is a guess, but the NIK and the birth date agree, which confirms
        // both. Nothing confirms the name, so only it is marked.
        #expect(result.needsCheck == [FieldKey.name])
    }

    /// Recognition drops the colon or reads it as a semicolon.
    @Test func labelsWithoutAColon() throws {
        for separator in ["", " ;", ";"] {
            let lines = [
                "NIK\(separator) 0012341708900001", "Nama\(separator) BUDI CONTOH",
                "Tempat/Tgl. Lahir\(separator) JAKARTA, 17-08-1990",
            ]
            let result = try #require(parse(lines), "\(separator)")
            #expect(result.fields.values[FieldKey.nik] == "0012341708900001", "\(separator)")
            #expect(result.fields.values[FieldKey.name] == "BUDI CONTOH", "\(separator)")
            #expect(result.fields.values[FieldKey.birthDate] == "1990-08-17", "\(separator)")
            #expect(result.needsCheck.isEmpty, "\(separator)")
        }
    }

    /// Recognition mixes up l, i, I, 1 and |; a label read as "Tgi" or "NlK" is still that label. Values
    /// aren't touched: this applies to labels only.
    @Test func labelsReadWithLookalikeLetters() throws {
        let lines = ["NlK : 0012341708900001", "Nama : BUDI CONTOH", "Tempat/Tgi Lahir : JAKARTA, 17-08-1990"]
        let result = try #require(parse(lines))
        #expect(result.fields.values[FieldKey.nik] == "0012341708900001")
        #expect(result.fields.values[FieldKey.birthDate] == "1990-08-17")
        #expect(result.needsCheck.isEmpty)
    }

    /// Seen on a real KTP: the label alone, and the place and date on the next line with no colon.
    @Test func aBirthDateOnTheNextLineIsConfirmedByTheNIK() throws {
        let lines = ["NIK : 0012341708900001", "Nama : BUDI CONTOH", "Tempat/Tgi Lahir", "JAKARTA, 17-08-1990"]
        let result = try #require(parse(lines))
        #expect(result.fields.values[FieldKey.birthDate] == "1990-08-17")
        #expect(result.needsCheck.isEmpty)
    }

    /// Without a NIK to confirm it, the pairing stays a guess.
    @Test func aBirthDateOnTheNextLineWithoutANIKIsMarked() throws {
        let lines = ["NIK : 00123417", "Nama : BUDI CONTOH", "Tempat/Tgl Lahir", "JAKARTA, 17-08-1990"]
        let result = try #require(parse(lines))
        #expect(result.needsCheck.contains(FieldKey.birthDate))
    }

    /// The same misread letter in the NIK and the date gives two wrong values that agree, so a corrected
    /// NIK can't confirm anything.
    @Test func aCorrectedNIKDoesntConfirmACorrectedBirthDate() throws {
        let result = try #require(parse(Self.card(nik: "0012341S08900001", birth: "JAKARTA, 1S-08-1990")))
        // Read, so the mark below comes from the confirmation rule and not from a date that wasn't found.
        #expect(result.fields.values[FieldKey.birthDate] == "1990-08-15")
        #expect(result.needsCheck.contains(FieldKey.nik))
        #expect(result.needsCheck.contains(FieldKey.birthDate))
    }

    /// A NIK whose pairing is a guess, with no birth date to confirm it, stays marked.
    @Test func aNIKOnTheNextLineWithoutABirthDateIsMarked() throws {
        let result = try #require(parse(["NIK", ": 0012341708900001", "Nama : BUDI CONTOH"]))
        #expect(result.fields.values[FieldKey.nik] == "0012341708900001")
        #expect(result.needsCheck.contains(FieldKey.nik))
    }

    /// Every letter the NIK reads in place of a digit is read in a date too.
    @Test func everyNIKLookalikeIsReadInADate() throws {
        // l, I and | are covered above.
        for (date, day) in [("O1", "01"), ("o1", "01"), ("D1", "01"), ("Z1", "21"), ("1S", "15"), ("1B", "18")] {
            let lines = Self.card(nik: "001234\(day)08900001", birth: "JAKARTA, \(date)-08-1990")
            let result = try #require(parse(lines), "\(date)")
            #expect(result.fields.values[FieldKey.birthDate] == "1990-08-\(day)", "\(date)")
        }
    }

    /// Seen on a real KTP: the first digit of the day read as a letter.
    @Test func aBirthDateWithALookalikeDigitIsCorrected() throws {
        for day in ["l7", "I7", "|7"] {
            let lines = Self.card(birth: "JAKARTA, \(day)-08-1990")
            let confirmed = try #require(parse(lines))
            #expect(confirmed.fields.values[FieldKey.birthDate] == "1990-08-17", "\(day)")
            #expect(confirmed.needsCheck.isEmpty, "\(day)")
        }
        // No NIK to confirm the correction, so it's marked.
        let unconfirmed = try #require(parse(Self.card(nik: "00123417", birth: "JAKARTA, l7-08-1990")))
        #expect(unconfirmed.fields.values[FieldKey.birthDate] == "1990-08-17")
        #expect(unconfirmed.needsCheck.contains(FieldKey.birthDate))
    }

    /// Recognition can return the label column before the value column. A label is never taken as a
    /// value, and the card is still a KTP, with everything marked.
    @Test func labelsBeforeValuesNeverTakeALabelAsAValue() throws {
        let lines = [
            "PROVINSI DKI JAKARTA", "NIK", "Nama", "Tempat/Tgl Lahir", ": 0012341708900001", ": BUDI CONTOH",
            ": JAKARTA, 17-08-1990",
        ]
        let result = try #require(parse(lines))
        #expect(result.fields.values[FieldKey.name] == nil)
        #expect(result.fields.values[FieldKey.nik] == nil)
        #expect(result.needsCheck == [FieldKey.nik, FieldKey.name, FieldKey.birthDate])
    }

    /// A long name wraps onto the next line; only its first part is read, so it's marked.
    /// A wrapped line that only starts with a label's letters isn't a label.
    @Test func aWrappedLineStartingLikeALabelIsStillAWrap() throws {
        let lines = ["NIK : 0012345708900002", "Nama : SITI", "NIKEN AYU", "Tempat/Tgl Lahir : JAKARTA, 17-08-1990"]
        let result = try #require(parse(lines))
        #expect(result.needsCheck == [FieldKey.name])
    }

    @Test func aNameThatWrapsIsMarked() throws {
        let lines = [
            "NIK : 0012341708900001", "Nama : BUDI CONTOH", "SANTOSO", "Tempat/Tgl Lahir : JAKARTA, 17-08-1990",
        ]
        let result = try #require(parse(lines))
        #expect(result.needsCheck == [FieldKey.name])
    }

    /// Women's NIKs carry the day of birth plus 40.
    @Test func aWomansNIKMatchesHerBirthDate() throws {
        let result = try #require(
            parse(Self.card(nik: "0012345708900002", name: "SITI CONTOH", sex: "PEREMPUAN")))
        #expect(result.needsCheck.isEmpty)
    }

    /// Day plus 40 is only for women, so the sex on the card catches a misread first digit of the day.
    @Test func aNIKThatDoesntMatchTheSexIsMarked() throws {
        let man = try #require(parse(Self.card(nik: "0012345708900001", sex: "LAKI-LAKI")))
        #expect(man.needsCheck == [FieldKey.nik])
        let woman = try #require(parse(Self.card(nik: "0012341708900002", sex: "PEREMPUAN")))
        #expect(woman.needsCheck == [FieldKey.nik])
    }

    @Test func aNIKThatDoesntMatchTheBirthDateIsMarked() throws {
        for birth in ["JAKARTA, 18-08-1990", "JAKARTA, 17-09-1990", "JAKARTA, 17-08-1991"] {
            let result = try #require(parse(Self.card(birth: birth)))
            #expect(result.needsCheck == [FieldKey.nik, FieldKey.birthDate], "\(birth)")
        }
    }

    /// Names are printed in capitals, so a leftover separator or a small letter is a misread.
    @Test func punctuationOrSmallLettersInTheNameAreMarked() throws {
        for name in [", BUDI CONTOH", ". BUDI", ": BUDI", "BUDl CONTOH"] {
            let result = try #require(parse(Self.card(name: name)))
            #expect(result.needsCheck == [FieldKey.name], "\(name)")
        }
        for name in ["M. RIZKI", "SITI NUR'AINI", "ANAK AGUNG GDE-PUTRA"] {
            let result = try #require(parse(Self.card(name: name)))
            #expect(result.needsCheck.isEmpty, "\(name)")
        }
    }

    @Test func aDigitInTheNameIsMarkedNotChanged() throws {
        let result = try #require(parse(Self.card(name: "BUDI C0NTOH")))
        #expect(result.fields.values[FieldKey.name] == "BUDI C0NTOH")
        #expect(result.needsCheck == [FieldKey.name])
    }

    @Test func otherSeparatorsInTheBirthDate() throws {
        for birth in ["JAKARTA, 17.08.1990", "JAKARTA, 17/08/1990", "JAKARTA,17-08-1990"] {
            let result = try #require(parse(Self.card(birth: birth)))
            #expect(result.fields.values[FieldKey.birthDate] == "1990-08-17", "\(birth)")
            #expect(result.needsCheck.isEmpty, "\(birth)")
        }
    }

    /// Stored like every date in the vault. A date that can't exist is left empty for the user.
    @Test func anImpossibleBirthDateIsMarkedAndLeftEmpty() throws {
        let result = try #require(parse(Self.card(birth: "JAKARTA, 31-02-1990")))
        #expect(result.fields.values[FieldKey.birthDate] == nil)
        #expect(result.needsCheck.contains(FieldKey.birthDate))
    }

    /// The NIK only holds the last two digits of the year, so a misread century has to be caught here.
    @Test func aBirthDateThatCantBeRightIsMarked() throws {
        for birth in ["JAKARTA, 17-08-1090", "JAKARTA, 17-08-2090", "JAKARTA, 17-08-1890"] {
            let result = try #require(parse(Self.card(birth: birth)))
            #expect(result.needsCheck.contains(FieldKey.birthDate), "\(birth)")
        }
    }

    /// Digits 7 to 12 are a date, day plus 40 for women, so day 99 or month 99 can't be right.
    @Test func aNIKWithAnImpossibleDateIsMarkedWithoutABirthDate() throws {
        for nik in [
            "0012349999900001", "0012343208900001", "0012341713900001", "0012347208900001", "0012340008900001",
            "0012341700900001",
        ] {
            let result = try #require(parse(["NIK : \(nik)", "Nama : BUDI CONTOH"]))
            #expect(result.needsCheck.contains(FieldKey.nik), "\(nik)")
        }
    }

    /// A corrected NIK is still compared with the birth date, so a bad correction shows on both.
    @Test func aCorrectedNIKIsStillCrossChecked() throws {
        let result = try #require(parse(Self.card(nik: "OO12341708SOOOOI")))
        #expect(result.needsCheck == [FieldKey.nik, FieldKey.birthDate])
    }

    @Test func missingLinesAreMarked() throws {
        let result = try #require(parse(["PROVINSI DKI JAKARTA", "NIK : 0012341708900001"]))
        #expect(result.fields.values[FieldKey.nik] == "0012341708900001")
        #expect(result.needsCheck == [FieldKey.name, FieldKey.birthDate])
    }

    @Test func notAKTP() {
        #expect(parse(["REPUBLIK INDONESIA", "PASPOR", "P<IDNCONTOH<<BUDI"]) == nil)
        #expect(parse([]) == nil)
    }
}
