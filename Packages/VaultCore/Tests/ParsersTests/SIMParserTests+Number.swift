//
//  SIMParserTests+Number.swift
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

    /// When neither layout shows, the number's length alone isn't a reason to mark it. Signs of both
    /// layouts mark every field instead (conflictingLayoutsMarkEveryField).
    @Test func anUnknownLayoutDoesntMarkTheNumbersLength() throws {
        let neither = ["SURAT IZIN MENGEMUDI", "A", "0000-0000-000001", "BUDI CONTOH", "04-01-2027"]
        #expect(try #require(parse(neither)).needsCheck.contains(FieldKey.simNumber) == false)
    }

    @Test func lookalikeLettersInTheNumberAreCorrectedAndMarked() throws {
        let result = try #require(parse(Self.oldCard(number: "OOOO-0000-00000I")))
        #expect(result.fields.values[FieldKey.simNumber] == "00000000000001")
        #expect(result.needsCheck == [FieldKey.simNumber])
    }

    @Test func aNumberOfTheWrongLengthIsMarked() throws {
        let result = try #require(parse(Self.oldCard(number: "0000-0000-0001")))
        #expect(result.needsCheck.contains(FieldKey.simNumber))
    }
}
