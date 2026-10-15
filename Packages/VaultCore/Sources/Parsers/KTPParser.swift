//
//  KTPParser.swift
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

/// Reads a KTP from its recognised text lines. It fills in what it can and marks what the user
/// should look at again; it never guesses silently.
public enum KTPParser {
    public static let nik = "nik"
    public static let name = "name"
    public static let birthDate = "birthDate"

    /// nil when the lines don't look like a KTP: there's no NIK label.
    public static func parse(_ lines: [String]) -> ParsedDocument? {
        guard let nikText = value(of: "NIK", in: lines) else { return nil }
        var fields: [String: String] = [:]
        var needsCheck: Set<String> = []

        let (number, corrected) = digits(from: nikText)
        fields[nik] = number
        if corrected || number.count != 16 || !number.allSatisfy(\.isASCIIDigit) { needsCheck.insert(nik) }

        if let nameText = value(of: "Nama", in: lines), !nameText.isEmpty {
            fields[name] = nameText
            // A digit is a misread letter, but which letter can't be known, so it's only marked.
            if nameText.contains(where: \.isASCIIDigit) { needsCheck.insert(name) }
        } else {
            needsCheck.insert(name)
        }

        let birth = value(of: "Tempat/Tgl Lahir", in: lines).flatMap(date(in:))
        if let birth {
            fields[birthDate] = birth.string
        } else {
            needsCheck.insert(birthDate)
        }

        if let birth, !needsCheck.contains(nik), !nikMatches(number, birth) {
            needsCheck.formUnion([nik, birthDate])
        }
        // A KTP is valid for life, so it has no expiry.
        return ParsedDocument(type: .ktp, fields: DocumentFields(fields), expiry: nil, needsCheck: needsCheck)
    }

    /// The text after a label, from "Label : value" or from the line after a "Label" line on its own.
    /// Labels are compared without case, spaces or dots, since recognition drops and adds those.
    static func value(of label: String, in lines: [String]) -> String? {
        let key = squeezed(label)
        for (index, line) in lines.enumerated() {
            let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard squeezed(String(parts[0])) == key else { continue }
            if parts.count == 2 {
                let text = parts[1].trimmingCharacters(in: .whitespaces)
                if !text.isEmpty { return text }
            }
            guard index + 1 < lines.count else { return nil }
            let next = lines[index + 1].trimmingCharacters(in: .whitespaces)
            return next.hasPrefix(":") ? next.dropFirst().trimmingCharacters(in: .whitespaces) : next
        }
        return nil
    }

    private static func squeezed(_ text: String) -> String {
        text.lowercased().filter { $0 != " " && $0 != "." }
    }

    /// Letters recognition often reads in place of digits on a NIK.
    private static let lookalikes: [Character: Character] = [
        "O": "0", "o": "0", "D": "0", "I": "1", "l": "1", "|": "1", "Z": "2", "S": "5", "B": "8",
    ]

    /// Drops spaces and swaps lookalike letters for digits. `corrected` says whether any were swapped.
    private static func digits(from text: String) -> (String, corrected: Bool) {
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

    /// The last dd-mm-yyyy in the text (the place of birth comes first), with -, . or / between.
    private static func date(in text: String) -> CalendarDate? {
        guard let match = text.matches(of: /(\d{2})[-.\/](\d{2})[-.\/](\d{4})/).last,
            let day = Int(match.1), let month = Int(match.2), let year = Int(match.3)
        else { return nil }
        return CalendarDate(year: year, month: month, day: day)
    }

    /// Digits 7 to 12 of a NIK are the date of birth as ddmmyy, with 40 added to the day for women.
    private static func nikMatches(_ number: String, _ birth: CalendarDate) -> Bool {
        let digits = number.compactMap(\.wholeNumberValue)
        guard digits.count == 16 else { return false }
        func pair(_ start: Int) -> Int { digits[start] * 10 + digits[start + 1] }
        let day = pair(6) > 40 ? pair(6) - 40 : pair(6)
        return day == birth.day && pair(8) == birth.month && pair(10) == birth.year % 100
    }
}

extension Character {
    fileprivate var isASCIIDigit: Bool { ("0"..."9").contains(self) }
}
