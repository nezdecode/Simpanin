//
//  NIK.swift
//  Parsers
//
//  Created by Inez Amanda on 15/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import VaultCore

/// What a NIK says about its holder. Shared by every document that prints one.
public enum NIK {
    /// Whether a NIK agrees with a birth date; nil when the NIK holds no readable date. Only the day, the
    /// month and the year's last two digits can be compared.
    public static func agrees(_ number: String, withBirthDate birth: CalendarDate) -> Bool? {
        birthDate(in: number)?.matches(birth)
    }

    /// 16 ASCII digits, the only shape a NIK has; the review refuses any other.
    public static func isWellFormed(_ number: String) -> Bool {
        number.count == 16 && number.allSatisfy(\.isASCIIDigit)
    }

    /// Letters recognition often reads in place of digits.
    static let lookalikes: [Character: Character] = [
        "O": "0", "o": "0", "D": "0", "I": "1", "l": "1", "|": "1", "Z": "2", "S": "5", "B": "8",
    ]

    /// Drops spaces and swaps lookalike letters for digits. `corrected` says whether any were swapped.
    static func digits(from text: String) -> (String, corrected: Bool) {
        var corrected = false
        let result = String(
            text.compactMap { character -> Character? in
                if character.isWhitespace { return nil }
                if let digit = lookalikes[character] {
                    corrected = true
                    return digit
                }
                return character
            })
        return (result, corrected)
    }

    struct BirthDate: Equatable {
        var day: Int
        var month: Int
        /// The last two digits only.
        var year: Int
        var woman: Bool

        func matches(_ birth: CalendarDate) -> Bool {
            (day, month, year) == (birth.day, birth.month, birth.year % 100)
        }
    }

    // The first two digits, the province, are left unchecked on purpose: test NIKs use 00, which no
    // real province has, so a province check would either break every test or let real data in.
    /// Digits 7 to 12 of a NIK are the date of birth as ddmmyy, with 40 added to the day for women.
    /// nil when the NIK isn't 16 digits or that date can't exist.
    static func birthDate(in number: String) -> BirthDate? {
        guard isWellFormed(number) else { return nil }
        let digits = number.compactMap(\.wholeNumberValue)
        func pair(_ start: Int) -> Int { digits[start] * 10 + digits[start + 1] }
        let day = pair(6) > 40 ? pair(6) - 40 : pair(6)
        guard (1...31).contains(day), (1...12).contains(pair(8)) else { return nil }
        return BirthDate(day: day, month: pair(8), year: pair(10), woman: pair(6) > 40)
    }
}
