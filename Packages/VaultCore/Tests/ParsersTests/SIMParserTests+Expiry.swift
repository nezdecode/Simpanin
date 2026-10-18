//
//  SIMParserTests+Expiry.swift
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
}
