//
//  SIMParserTests+OldCards.swift
//  ParsersTests
//
//  Created by Inez Amanda on 17/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Parsers
import Testing
import VaultCore

/// Older cards as Vision reads them: line numbers dropped or misread, noise lines, the expiry alone at the
/// bottom. Synthetic text in the shapes of two real scans.
extension SIMParserTests {
    /// The first scan's shape: no "1." before the name, "2." before the birth line.
    static func withoutNameNumber(
        number: String = "0000-0000-000001", name: [String] = ["BUDI CONTOH"], birth: String = "2. JAKARTA, 17-08-1990",
        expiry: [String] = ["04-01-2027"]
    ) -> [String] {
        ["INDONESIA", "DRIVING LICENSE", "SURAT IZIN MENGEMUDI", "C", number] + name
            + [birth, "3. - - PRIA", "JL. CONTOH NO. 1", "RT 01/02", "KOTA CONTOH", "KARYAWAN", "6. METRO"] + expiry
    }

    /// The second scan's shape: "1." kept, a noise line under the name, no "2.", "3." alone on its line,
    /// "6." with its digit lost.
    static func withoutBirthNumber(birth: [String] = ["JAKARTA, 17-08-1990"], beforeBirth: [String] = []) -> [String] {
        ["INDONESIA", "DRIVING LICENSE", "SURAT IZIN MENGEMUDI", "C", "0000-0000-000001", "1. BUDI CONTOH", "~"]
            + beforeBirth + birth
            + ["3.", "- - PRIA", "JL. CONTOH NO. 1", "RT 01/02", "KOTA CONTOH", "KARYAWAN", ". METRO", "04-01-2027"]
    }

    func expectFull(_ result: ParsedDocument) {
        #expect(result.fields.values[FieldKey.name] == "BUDI CONTOH")
        #expect(result.fields.values[FieldKey.birthDate] == "1990-08-17")
        #expect(result.expiry == CalendarDate(year: 2027, month: 1, day: 4))
        #expect(!result.expiryNeedsCheck)
    }

    // MARK: The name

    @Test func anOldCardWithoutTheNameNumber() throws {
        let result = try #require(parse(Self.withoutNameNumber()))
        expectFull(result)
    }

    /// Its place confirms which line is the name, and nothing in it was corrected, so it isn't marked.
    @Test func aNameBetweenTheNumberAndTheBirthLineIsntMarked() throws {
        let result = try #require(parse(Self.withoutNameNumber()))
        #expect(!result.needsCheck.contains(FieldKey.name))
    }

    /// The place says which line, not that its letters were read right.
    @Test func aNameWithCharactersOutsideANameIsMarked() throws {
        let result = try #require(parse(Self.withoutNameNumber(name: ["BUDI C0NTOH"])))
        #expect(result.needsCheck.contains(FieldKey.name))
    }

    @Test func twoLinesBetweenTheNumberAndTheBirthLineMarkTheName() throws {
        let result = try #require(parse(Self.withoutNameNumber(name: ["BUDI", "CONTOH"])))
        #expect(result.needsCheck.contains(FieldKey.name))
    }

    /// A line number read into the name is removed, and the name marked: a correction confirms nothing.
    @Test(arguments: ["1BUDI CONTOH", "I. BUDI CONTOH", "l. BUDI CONTOH"])
    func aLineNumberStuckToTheNameIsRemovedAndMarked(_ line: String) throws {
        let result = try #require(parse(Self.withoutNameNumber(name: [line])))
        #expect(result.fields.values[FieldKey.name] == "BUDI CONTOH")
        #expect(result.needsCheck.contains(FieldKey.name))
    }

    /// A line with no letter and no digit is noise; it never continues the name.
    @Test func aNoiseLineDoesntContinueTheName() throws {
        let result = try #require(parse(Self.withoutBirthNumber()))
        #expect(result.fields.values[FieldKey.name] == "BUDI CONTOH")
        #expect(!result.needsCheck.contains(FieldKey.name))
    }

    /// Noise is told by having no letter or digit, never by length.
    @Test func aShortNameIsntNoise() throws {
        let result = try #require(parse(Self.withoutNameNumber(name: ["AN"])))
        #expect(result.fields.values[FieldKey.name] == "AN")
        #expect(!result.needsCheck.contains(FieldKey.name))
    }

    /// A field number read alone on its line is no part of the name, though its place still marks it.
    @Test(arguments: [["1.", "BUDI CONTOH"], ["BUDI CONTOH", "2."]])
    func aFieldNumberAloneIsntPartOfTheName(_ name: [String]) throws {
        let result = try #require(parse(Self.withoutNameNumber(name: name, birth: "JAKARTA, 17-08-1990")))
        #expect(result.fields.values[FieldKey.name] == "BUDI CONTOH")
        #expect(result.needsCheck.contains(FieldKey.name))
    }

    /// A name that isn't there is left out, never stored empty.
    @Test func aMissingNameIsntStoredEmpty() throws {
        let result = try #require(parse(Self.withoutNameNumber(name: ["1."], birth: "JAKARTA, 17-08-1990")))
        #expect(result.fields.values[FieldKey.name] == nil)
        #expect(result.needsCheck.contains(FieldKey.name))
    }

    /// Without a number, nothing says which line is the name, so none is guessed.
    @Test func anOldCardWithoutANumberLeavesTheNameEmpty() throws {
        var lines = Self.withoutNameNumber()
        lines.removeAll { $0 == "0000-0000-000001" }
        let result = try #require(parse(lines))
        #expect(result.fields.values[FieldKey.name] == nil)
        #expect(result.needsCheck.contains(FieldKey.name))
    }

    // MARK: The birth date

    @Test func anOldCardWithoutTheBirthNumber() throws {
        let result = try #require(parse(Self.withoutBirthNumber()))
        expectFull(result)
    }

    @Test func aBirthLineWithoutItsCommaIsRead() throws {
        let result = try #require(parse(Self.withoutBirthNumber(birth: ["JAKARTA 17-08-1990"])))
        #expect(result.fields.values[FieldKey.birthDate] == "1990-08-17")
    }

    /// A place and date read onto two lines is left empty and marked rather than pieced together.
    @Test func aBirthDateSplitOverTwoLinesIsMarked() throws {
        let result = try #require(parse(Self.withoutBirthNumber(birth: ["JAKARTA,", "17-08-1990"])))
        #expect(result.fields.values[FieldKey.birthDate] == nil)
        #expect(result.needsCheck.contains(FieldKey.birthDate))
        #expect(result.expiry == nil || result.expiryNeedsCheck)
    }

    // MARK: The expiry

    @Test func aBirthLineFoundByItsShapeIsNeverTheExpiry() throws {
        let result = try #require(parse(Self.withoutBirthNumber()))
        #expect(result.expiry == CalendarDate(year: 2027, month: 1, day: 4))
    }

    /// The expiry comes after the birth line; a date above it is something else.
    @Test func aDateBeforeTheBirthLineIsntTheExpiry() throws {
        let result = try #require(parse(Self.withoutBirthNumber(beforeBirth: ["01-01-2020"])))
        #expect(result.expiry == CalendarDate(year: 2027, month: 1, day: 4))
    }

    @Test func aCardCutOffAtTheBottomHasNoExpiryAndIsMarked() throws {
        let result = try #require(parse(Self.withoutNameNumber(expiry: [])))
        #expect(result.expiry == nil)
        #expect(result.expiryNeedsCheck)
    }

    // MARK: The layout

    /// A card read bottom to top may lose values, but never gives a wrong one unmarked.
    @Test func linesInReverseOrderGiveNoUnmarkedValue() throws {
        let result = try #require(parse(Self.withoutNameNumber().reversed()))
        let right = ["BUDI CONTOH", "1990-08-17"]
        for key in [FieldKey.name, FieldKey.birthDate] {
            let value = result.fields.values[key]
            #expect(value == nil || right.contains(value!) || result.needsCheck.contains(key), "\(key)")
        }
        #expect(
            result.expiry == nil || result.expiry == CalendarDate(year: 2027, month: 1, day: 4)
                || result.expiryNeedsCheck)
    }

    /// Signs of both layouts at once: the rules aren't mixed, and every field is marked.
    @Test(arguments: [
        withoutNameNumber() + ["Nama/Name"],
        withoutNameNumber(number: "0012341708900001"),
    ])
    func conflictingLayoutsMarkEveryField(_ lines: [String]) throws {
        let result = try #require(parse(lines))
        #expect(result.needsCheck.isSuperset(of: [FieldKey.simNumber, FieldKey.name, FieldKey.birthDate]))
        #expect(result.expiryNeedsCheck)
    }

    /// Nothing in the known shapes: nothing is guessed.
    @Test func anUnknownLayoutGuessesNothing() throws {
        let lines = ["INDONESIA", "SURAT IZIN MENGEMUDI", "C", "BUDI CONTOH", "17-08-1990", "04-01-2027"]
        let result = try #require(parse(lines))
        #expect(result.fields.values[FieldKey.name] == nil)
        #expect(result.fields.values[FieldKey.birthDate] == nil)
        #expect(result.expiry == nil)
    }

    // MARK: The number

    /// Stored as its digits alone, however it was printed or read; the dashes are only for display.
    @Test(arguments: [
        ("0000-0000-000001", false), ("0000 0000 000001", false), ("00000000000001", false), ("OOOO-0000-000001", true),
    ])
    func anOldNumberIsStoredAsDigitsOnly(_ printed: String, corrected: Bool) throws {
        let result = try #require(parse(Self.oldCard(number: printed)))
        #expect(result.fields.values[FieldKey.simNumber] == "00000000000001")
        #expect(result.needsCheck.contains(FieldKey.simNumber) == corrected)
    }
}
