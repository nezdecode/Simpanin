//
//  CheckReasonTests.swift
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

@Suite("Check reasons")
struct CheckReasonTests {
    /// The app's texts are looked up by these, so renaming one shows its key instead of its text.
    @Test func rawValuesArePinned() {
        #expect(
            CheckReason.allCases.map(\.rawValue) == [
                "mixedLayout", "impossibleDate", "disagreesWithBirthDate", "sexDisagrees", "implausibleExpiry",
                "noDateInNumber", "lookalike", "oddCharacters", "severalNumbers", "severalDates", "classUnclear",
                "noDocumentRecognized", "notFound", "readFromAnotherLine", "expiryUnconfirmed", "mayContinue",
            ])
    }

    /// The order decided on 19 Oct, tested only on pairs that can meet on one value.
    @Test func theFirstCaseWins() {
        let pairs: [(shown: CheckReason, other: CheckReason)] = [
            (.mixedLayout, .disagreesWithBirthDate),  // a SIM's number or birth date
            (.impossibleDate, .readFromAnotherLine),  // a KTP's birth date
            (.disagreesWithBirthDate, .lookalike),  // a corrected NIK
            (.sexDisagrees, .readFromAnotherLine),  // a NIK on the next line
            (.mixedLayout, .implausibleExpiry),  // a SIM's expiry
            (.lookalike, .severalNumbers),  // a SIM's number
            (.oddCharacters, .mayContinue),  // a name
            (.mixedLayout, .classUnclear),  // a SIM's type
            (.readFromAnotherLine, .mayContinue),  // a KTP's name
        ]
        for pair in pairs {
            #expect(pair.shown < pair.other, "\(pair.shown) before \(pair.other)")
            #expect(Set([pair.other, pair.shown]).min() == pair.shown)
        }
    }
}
