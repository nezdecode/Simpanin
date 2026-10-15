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
    public static func parse(_ lines: [String], today: CalendarDate) -> ParsedDocument? {
        guard lines.contains(where: { label("NIK", startsLine: $0) != nil }) else { return nil }
        var fields: [String: String] = [:]
        var needsCheck: Set<String> = []

        var number = ""
        if let found = value(of: "NIK", in: lines) {
            let (digits, corrected) = digits(from: found.text)
            number = digits
            fields[nik] = number
            if found.fromNextLine || corrected { needsCheck.insert(nik) }
        }
        if number.count != 16 || !number.allSatisfy(\.isASCIIDigit) { needsCheck.insert(nik) }

        if let found = value(of: "Nama", in: lines) {
            fields[name] = found.text
            // A digit is a misread letter, but which letter can't be known, so it's only marked.
            if found.fromNextLine || found.continues || found.text.contains(where: \.isASCIIDigit) {
                needsCheck.insert(name)
            }
        } else {
            needsCheck.insert(name)
        }

        let birthText = value(of: "Tempat/Tgl Lahir", in: lines)
        let birth = birthText.flatMap { date(in: $0.text) }
        if let birth {
            fields[birthDate] = birth.string
            // The NIK only holds the last two digits of the year, so a misread century passes the cross-check.
            let plausible = birth.year >= 1900 && birth <= today
            if birthText?.fromNextLine == true || !plausible { needsCheck.insert(birthDate) }
        } else {
            needsCheck.insert(birthDate)
        }

        if let birth, !needsCheck.contains(nik), !nikMatches(number, birth) {
            needsCheck.formUnion([nik, birthDate])
        }
        // A KTP is valid for life, so it has no expiry.
        return ParsedDocument(type: .ktp, fields: DocumentFields(fields), expiry: nil, needsCheck: needsCheck)
    }

    /// Every label on the front of a KTP, so a label line is never taken as another label's value.
    private static let labels = [
        "NIK", "Nama", "Tempat/Tgl Lahir", "Jenis Kelamin", "Gol Darah", "Alamat", "RT/RW", "Kel/Desa", "Kecamatan",
        "Agama", "Status Perkawinan", "Pekerjaan", "Kewarganegaraan", "Berlaku Hingga",
    ]

    private struct Found {
        var text: String
        /// The value sat on the line after its label, so which line belongs to it is a guess.
        var fromNextLine = false
        /// The line after the value isn't a label, so the value may go on there.
        var continues = false
    }

    /// The text after a label, from "Label : value" or from the line after a label on its own. Never
    /// another label: recognition can return the label column before the value column.
    private static func value(of wanted: String, in lines: [String]) -> Found? {
        for (index, line) in lines.enumerated() {
            guard let rest = label(wanted, startsLine: line) else { continue }
            let next = index + 1 < lines.count ? lines[index + 1] : nil
            let nextIsLabel = next.map(isLabel) ?? true
            if !rest.isEmpty { return Found(text: rest, continues: !nextIsLabel) }
            guard let next, !nextIsLabel else { return nil }
            var text = Substring(next.trimmingCharacters(in: .whitespaces))
            if text.first == ":" || text.first == ";" { text = text.dropFirst() }
            let value = text.trimmingCharacters(in: .whitespaces)
            return value.isEmpty ? nil : Found(text: value, fromNextLine: true)
        }
        return nil
    }

    private static func isLabel(_ line: String) -> Bool {
        labels.contains { label($0, startsLine: line) != nil }
    }

    /// The rest of the line when it starts with the label, or nil. Recognition drops and adds spaces
    /// and dots, and reads the colon as a semicolon or drops it, so all of those are allowed.
    private static func label(_ label: String, startsLine line: String) -> String? {
        let letters = label.filter { $0 != " " && $0 != "." }.map {
            NSRegularExpression.escapedPattern(for: String($0))
        }
        let pattern = "^\\s*" + letters.joined(separator: "[\\s.]*") + "(?:[\\s.]*[:;]|\\s+|$)(.*)$"
        guard let regex = try? Regex(pattern).ignoresCase(),
            let match = try? regex.wholeMatch(in: line),
            let rest = match.output[1].substring
        else { return nil }
        return rest.trimmingCharacters(in: .whitespaces)
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
