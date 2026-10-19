//
//  KTPParserTests+Reasons.swift
//  ParsersTests
//
//  Created by Inez Amanda on 19/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Parsers
import Testing
import VaultCore

/// Why each mark was made, which the review screen shows under the field.
extension KTPParserTests {
    @Test func aCleanCardHasNoReasons() throws {
        let result = try #require(parse(Self.card()))
        #expect(result.reasons.isEmpty)
    }

    @Test func aMissingNIKGivesNotFound() throws {
        let result = try #require(parse(["NIK :", "Nama : BUDI CONTOH", "Tempat/Tgl Lahir : JAKARTA, 17-08-1990"]))
        #expect(result.reasons[FieldKey.nik] == [.notFound])
    }

    /// The review screen refuses these with "NIK harus 16 angka." as soon as it opens, which replaces a mark.
    @Test func aNIKOfTheWrongLengthOrWithALetterLeftGetsNoMark() throws {
        for nik in ["00123417089000", "0012341708900X01"] {
            let result = try #require(parse(Self.card(nik: nik)))
            #expect(result.reasons[FieldKey.nik] == nil, "\(nik)")
        }
    }

    @Test func aNIKWithoutADateGivesNoDateInNumber() throws {
        let result = try #require(parse(["NIK : 0012349999900001", "Nama : BUDI CONTOH"]))
        #expect(result.reasons[FieldKey.nik] == [.noDateInNumber])
    }

    @Test func aLookalikeInTheNIKGivesLookalike() throws {
        let result = try #require(parse(Self.card(nik: "0012341708900OO1")))
        #expect(result.reasons[FieldKey.nik] == [.lookalike])
    }

    @Test func aSexThatDisagreesWithTheNIKGivesSexDisagrees() throws {
        let result = try #require(parse(Self.card(nik: "0012345708900001", sex: "LAKI-LAKI")))
        #expect(result.reasons[FieldKey.nik] == [.sexDisagrees])
    }

    @Test func aNIKFromTheNextLineUnconfirmedGivesReadFromAnotherLine() throws {
        let result = try #require(parse(["NIK", ": 0012341708900001", "Nama : BUDI CONTOH"]))
        #expect(result.reasons[FieldKey.nik] == [.readFromAnotherLine])
    }

    @Test func aNIKAndBirthDateThatDisagreeMarkBothWithDisagreement() throws {
        let result = try #require(parse(Self.card(birth: "JAKARTA, 18-08-1990")))
        #expect(result.reasons[FieldKey.nik] == [.disagreesWithBirthDate])
        #expect(result.reasons[FieldKey.birthDate] == [.disagreesWithBirthDate])
    }

    /// Both are kept, so a birth date fixed to match still leaves the correction marked; the disagreement
    /// is shown first.
    @Test func aCorrectedNIKThatDisagreesKeepsBothReasons() throws {
        let result = try #require(parse(Self.card(nik: "OO12341708SOOOOI")))
        let nik = try #require(result.reasons[FieldKey.nik])
        #expect(nik == [.lookalike, .disagreesWithBirthDate])
        #expect(nik.min() == .disagreesWithBirthDate)
    }

    @Test func aNameFromTheNextLineGivesReadFromAnotherLine() throws {
        let lines = ["NIK : 0012341708900001", "Nama", ": BUDI CONTOH", "Tempat/Tgl Lahir : JAKARTA, 17-08-1990"]
        let result = try #require(parse(lines))
        #expect(result.reasons[FieldKey.name] == [.readFromAnotherLine])
    }

    @Test func aNameThatMayContinueGivesMayContinue() throws {
        let lines = [
            "NIK : 0012341708900001", "Nama : BUDI CONTOH", "SANTOSO", "Tempat/Tgl Lahir : JAKARTA, 17-08-1990",
        ]
        let result = try #require(parse(lines))
        #expect(result.reasons[FieldKey.name] == [.mayContinue])
    }

    @Test func oddCharactersInANameGiveOddCharacters() throws {
        let result = try #require(parse(Self.card(name: "BUDI C0NTOH")))
        #expect(result.reasons[FieldKey.name] == [.oddCharacters])
    }

    @Test func aMissingNameOrBirthDateGivesNotFound() throws {
        let result = try #require(parse(["PROVINSI DKI JAKARTA", "NIK : 0012341708900001"]))
        #expect(result.reasons[FieldKey.name] == [.notFound])
        #expect(result.reasons[FieldKey.birthDate] == [.notFound])
    }

    /// The NIK agrees on the day, month and last two digits, so the century is caught only here.
    @Test func aBirthDateBefore1900OrAfterTodayGivesImpossibleDate() throws {
        for birth in ["JAKARTA, 17-08-1890", "JAKARTA, 17-08-2090"] {
            let result = try #require(parse(Self.card(birth: birth)))
            #expect(result.reasons[FieldKey.birthDate] == [.impossibleDate], "\(birth)")
        }
    }

    @Test func aCorrectedBirthDateTheNIKDoesntConfirmGivesLookalike() throws {
        let result = try #require(parse(Self.card(nik: "00123417", birth: "JAKARTA, l7-08-1990")))
        #expect(result.reasons[FieldKey.birthDate] == [.lookalike])
    }

    @Test func aBirthDateFromTheNextLineUnconfirmedGivesReadFromAnotherLine() throws {
        let lines = ["NIK : 00123417", "Nama : BUDI CONTOH", "Tempat/Tgl Lahir", "JAKARTA, 17-08-1990"]
        let result = try #require(parse(lines))
        #expect(result.reasons[FieldKey.birthDate] == [.readFromAnotherLine])
    }
}
