//
//  SIMParserTests+NameAndBirthDate.swift
//  ParsersTests
//
//  Created by Inez Amanda on 18/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Parsers
import Testing
import VaultCore

/// The older layout has its own tests for this in SIMParserTests+OldCards.
extension SIMParserTests {
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

    /// The same misread letter in the number and the date gives two wrong values that agree, so a
    /// corrected number confirms nothing.
    @Test func aCorrectedNumberDoesntConfirmACorrectedBirthDate() throws {
        let result = try #require(parse(Self.newCard(number: "0012341S08900001", birth: "JAKARTA, 1S-08-1990")))
        #expect(result.fields.values[FieldKey.birthDate] == "1990-08-15")
        #expect(result.needsCheck.contains(FieldKey.birthDate))
    }

    @Test func aBirthDateThatCantBeRightIsMarked() throws {
        for birth in ["JAKARTA, 17-08-1090", "JAKARTA, 17-08-2090", "JAKARTA, 31-02-1990"] {
            let result = try #require(parse(Self.oldCard(birth: birth)))
            #expect(result.needsCheck.contains(FieldKey.birthDate), "\(birth)")
        }
    }
}
