//
//  DocumentNumberTests.swift
//  SimpaninTests
//
//  Created by Inez Amanda on 28/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import Testing

@testable import Simpanin

/// Synthetic numbers only; NIKs start with 00.
@Suite("Document number")
struct DocumentNumberTests {
    @Test func nikShownInGroupsOfFour() {
        #expect(DocumentNumber("0012341708900001").shown == "0012 3417 0890 0001")
    }

    @Test func sixteenDigitSIMShownLikeNIK() {
        #expect(DocumentNumber("0000-1234-5678-0001").shown == "0000 1234 5678 0001")
    }

    @Test func olderSIMShownWithDashes() {
        #expect(DocumentNumber("00123456789012").shown == "0012-3456-789012")
    }

    @Test func olderSIMMaskedWithDashes() {
        #expect(DocumentNumber("00123456789012").masked == "0012-••••-••9012")
    }

    @Test func otherLengthsInGroupsOfFour() {
        #expect(DocumentNumber("001234567890").shown == "0012 3456 7890")
        #expect(DocumentNumber("001234567890123").shown == "0012 3456 7890 123")
        #expect(DocumentNumber("001234567890123456").shown == "0012 3456 7890 1234 56")
    }

    @Test func maskedShowsFirstAndLastFour() {
        #expect(DocumentNumber("0012341708900001").masked == "0012 •••• •••• 0001")
        #expect(DocumentNumber("001234567890123").masked == "0012 •••• •••0 123")
    }

    /// Showing the first four as well would leave only a few digits hidden.
    @Test func belowFourteenDigitsOnlyTheLastFourShow() {
        #expect(DocumentNumber("0012345678901").masked == "•••• •••• •890 1")
        #expect(DocumentNumber("001234567").masked == "•••• •456 7")
    }

    /// The masked form is built without the hidden digits, so no label or value can leak them.
    @Test(arguments: ["0012341708900001", "00123456789012", "0012345678901", "001234567", "001234567890123456"])
    func maskedFormHoldsNoHiddenDigit(_ stored: String) {
        let number = DocumentNumber(stored)
        #expect(number.masked.count == number.shown.count)
        #expect(number.masked.count > stored.count)
        let kept =
            number.digits.count >= 14 ? number.digits.prefix(4) + number.digits.suffix(4) : number.digits.suffix(4)
        #expect(String(number.masked.filter(\.isNumber)) == String(kept))
    }

    /// Exactly what DuplicateCheck and Periksa data keep: ASCII digits, nothing else.
    @Test func everyNonDigitIsDropped() {
        let number = DocumentNumber(" 0012-3417.0890/0001\n")
        #expect(number.digits == "0012341708900001")
        #expect(DocumentNumber("٠٠١٢ 0012").digits == "0012")
        #expect(DocumentNumber("００12").digits == "12")
    }

    @Test func copiedFormIsDigitsOnly() {
        #expect(DocumentNumber("0012 3417-0890 0001").copied == "0012341708900001")
        #expect(DocumentNumber("0012-3456-789012").copied == "00123456789012")
    }

    @Test func noDigitsMeansEmpty() {
        for stored in ["", "  ", "-- --", "NIK"] {
            let number = DocumentNumber(stored)
            #expect(number.isEmpty, "\(stored)")
            #expect(number.shown.isEmpty)
            #expect(number.masked.isEmpty)
            #expect(number.copied.isEmpty)
        }
        #expect(!DocumentNumber("0012").isEmpty)
    }
}
