//
//  SIMParserTests+Reasons.swift
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
extension SIMParserTests {
    @Test func cleanCardsHaveNoReasons() throws {
        for lines in [Self.oldCard(), Self.newCard()] {
            let result = try #require(parse(lines))
            #expect(result.reasons.isEmpty)
            #expect(result.typeReasons.isEmpty)
            #expect(result.expiryReasons.isEmpty)
        }
    }

    // MARK: The number

    @Test func aMissingNumberGivesNotFound() throws {
        let result = try #require(parse(Self.oldCard(number: "0000-0000-0001")))
        #expect(result.reasons[FieldKey.simNumber] == [.notFound])
    }

    @Test func aLookalikeInTheNumberGivesLookalike() throws {
        let result = try #require(parse(Self.oldCard(number: "OOOO-0000-00000I")))
        #expect(result.reasons[FieldKey.simNumber] == [.lookalike])
    }

    @Test func severalNumbersGiveSeveralNumbers() throws {
        var lines = Self.oldCard()
        lines.insert("0000-0000-000009", at: 5)
        let result = try #require(parse(lines))
        #expect(result.reasons[FieldKey.simNumber]?.contains(.severalNumbers) == true)
    }

    @Test func aSixteenDigitNumberWithoutADateGivesNoDateInNumber() throws {
        let result = try #require(parse(Self.newCard(number: "0012349999900001")))
        #expect(result.reasons[FieldKey.simNumber] == [.noDateInNumber])
    }

    @Test func aSexThatDisagreesWithTheNumberGivesSexDisagrees() throws {
        let result = try #require(parse(Self.newCard(sex: "WANITA")))
        #expect(result.reasons[FieldKey.simNumber] == [.sexDisagrees])
    }

    @Test func aNumberAndBirthDateThatDisagreeMarkBoth() throws {
        let result = try #require(parse(Self.newCard(birth: "JAKARTA, 18-08-1990")))
        #expect(result.reasons[FieldKey.simNumber] == [.disagreesWithBirthDate])
        #expect(result.reasons[FieldKey.birthDate] == [.disagreesWithBirthDate])
    }

    // MARK: The name

    @Test func aMissingNameGivesNotFound() throws {
        let result = try #require(parse(Self.withoutNameNumber(name: ["1."], birth: "JAKARTA, 17-08-1990")))
        #expect(result.reasons[FieldKey.name] == [.notFound])
    }

    @Test func aNameOnTwoLinesGivesMayContinue() throws {
        let result = try #require(parse(Self.withoutNameNumber(name: ["BUDI", "CONTOH"])))
        #expect(result.reasons[FieldKey.name] == [.mayContinue])
    }

    /// A line number read into the name is a misread, not a second line.
    @Test(arguments: [["1BUDI CONTOH"], ["I. BUDI CONTOH"], ["1.", "BUDI CONTOH"]])
    func aStrippedLineNumberGivesOddCharacters(_ name: [String]) throws {
        let result = try #require(parse(Self.withoutNameNumber(name: name, birth: "JAKARTA, 17-08-1990")))
        #expect(result.reasons[FieldKey.name] == [.oddCharacters])
    }

    @Test func oddCharactersInANameGiveOddCharacters() throws {
        let result = try #require(parse(Self.newCard(name: "BUDI C0NTOH")))
        #expect(result.reasons[FieldKey.name] == [.oddCharacters])
    }

    // MARK: The birth date

    @Test func aMissingOrImpossibleBirthDateGivesNotFound() throws {
        let result = try #require(parse(Self.oldCard(birth: "JAKARTA, 31-02-1990")))
        #expect(result.reasons[FieldKey.birthDate] == [.notFound])
    }

    @Test func aBirthDateBefore1900OrAfterTodayGivesImpossibleDate() throws {
        for birth in ["JAKARTA, 17-08-1090", "JAKARTA, 17-08-2090"] {
            let result = try #require(parse(Self.oldCard(birth: birth)))
            #expect(result.reasons[FieldKey.birthDate]?.contains(.impossibleDate) == true, "\(birth)")
        }
    }

    @Test func aCorrectedBirthDateUnconfirmedGivesLookalike() throws {
        let result = try #require(parse(Self.oldCard(birth: "JAKARTA, l7-08-1990")))
        #expect(result.reasons[FieldKey.birthDate] == [.lookalike])
    }

    // MARK: The class

    @Test func anUnreadClassGivesClassUnclear() throws {
        let result = try #require(parse(Self.oldCard(classLine: "X")))
        #expect(result.typeReasons == [.classUnclear])
    }

    @Test func aCorrectedClassGivesLookalike() throws {
        let result = try #require(parse(Self.oldCard(classLine: "B1")))
        #expect(result.typeReasons == [.lookalike])
    }

    /// Without the name label, a blood type could be the only class-like line.
    @Test func noPlaceForTheClassGivesClassUnclear() throws {
        var lines = Self.newCard(classLine: "")
        let nameLabel = try #require(lines.firstIndex(of: "Nama/Name"))
        lines[nameLabel] = "Nana/Nane"
        let result = try #require(parse(lines))
        #expect(result.typeReasons.contains(.classUnclear))
    }

    // MARK: The layout

    @Test func mixedLayoutsGiveMixedLayoutOnEveryFieldTypeAndExpiry() throws {
        for lines in [Self.newCard(number: "00123417089000"), Self.oldCard(number: "0012341708900001")] {
            let result = try #require(parse(lines))
            for key in [FieldKey.simNumber, FieldKey.name, FieldKey.birthDate] {
                #expect(result.reasons[key]?.min() == .mixedLayout, "\(key)")
            }
            #expect(result.typeReasons.min() == .mixedLayout)
            #expect(result.expiryReasons.min() == .mixedLayout)
        }
    }

    // MARK: The expiry

    @Test func aMissingExpiryGivesNotFound() throws {
        for lines in [Self.oldCard(expiry: ""), Self.newCard(expiry: "")] {
            let result = try #require(parse(lines))
            #expect(result.expiryReasons == [.notFound])
        }
    }

    @Test func twoExpiryDatesGiveSeveralDates() throws {
        for var lines in [Self.oldCard(), Self.newCard()] {
            lines.append("05-01-2028")
            let result = try #require(parse(lines))
            #expect(result.expiryReasons == [.severalDates])
        }
    }

    @Test func anImplausibleExpiryGivesImplausibleExpiry() throws {
        for expiry in ["04-01-2005", "04-01-2037"] {
            let result = try #require(parse(Self.oldCard(expiry: expiry)))
            #expect(result.expiryReasons == [.implausibleExpiry], "\(expiry)")
        }
    }

    /// Without the birth date, the one date left may be the birth date itself.
    @Test func anExpiryWithoutABirthDateGivesExpiryUnconfirmed() throws {
        var lines = Self.newCard()
        let birthLabel = try #require(lines.firstIndex(of: "Tempat, Tgl Lahir/Place, Date of Birth"))
        lines.remove(at: birthLabel + 1)
        let result = try #require(parse(lines))
        #expect(result.expiry != nil)
        #expect(result.expiryReasons == [.expiryUnconfirmed])
    }
}
