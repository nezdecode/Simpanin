//
//  FieldDates.swift
//  Simpanin
//
//  Created by Inez Amanda on 27/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import Parsers
import VaultCore

/// How a date field is typed and stored: day first on screen, as on the card, YYYY-MM-DD in the vault.
nonisolated enum FieldDates {
    /// Digits as dd-mm-yyyy, for a number pad. A dash only goes before a digit, so backspace can remove it.
    static func typedDate(_ text: String) -> String {
        var result = ""
        let digits = text.filter(\.isASCIIDigit)
        for (index, digit) in digits.prefix(8).enumerated() {
            if index == 2 || index == 4 { result.append("-") }
            result.append(digit)
        }
        return result
    }

    /// Fields holding a date: shown day first, as on the card, and stored as YYYY-MM-DD like every date
    /// in the vault.
    static let dateKeys: Set<String> = [FieldKey.birthDate]

    /// "17-08-1990", also with dots, slashes or spaces between; nil when the date can't exist.
    static func yearFirst(_ typed: String) -> String? {
        guard let match = typed.wholeMatch(of: /\s*([0-9]{1,2})[-.\/ ]([0-9]{1,2})[-.\/ ]([0-9]{4})\s*/),
            let day = Int(match.1), let month = Int(match.2), let year = Int(match.3)
        else { return nil }
        return CalendarDate(year: year, month: month, day: day)?.string
    }
}
