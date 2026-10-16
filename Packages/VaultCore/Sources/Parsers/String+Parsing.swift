//
//  String+Parsing.swift
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

extension String {
    /// The last date in the text (a place usually comes first): dd-mm-yyyy with -, . or / between,
    /// or a day, a month name in Indonesian or English, and a year.
    var lastDate: CalendarDate? {
        var found: [(at: String.Index, date: CalendarDate?)] = []
        // \d also matches full-width and other digits. Capturing the whole run makes Int fail and the
        // date come back nil, so it's marked, where [0-9] would skip a digit and read a shorter, wrong date.
        for match in matches(of: /(\d{2})[-.\/](\d{2})[-.\/](\d{4})/) {
            let (_, day, month, year) = match.output
            found.append((match.range.lowerBound, Self.date(day, Int(month), year)))
        }
        for match in matches(of: /(\d+)\s+([A-Za-z]+)\s+(\d{4})/) {
            let (_, day, name, year) = match.output
            guard let month = Self.monthNumbers[name.uppercased()] else { continue }
            found.append((match.range.lowerBound, Self.date(day, month, year)))
        }
        return found.max { $0.at < $1.at }?.date
    }

    /// Like `lastDate`, but when there's no clean date it also reads letters recognition puts in place of
    /// digits, as in "l7-08-1990". `corrected` says whether any were swapped: a correction is a guess.
    var lastDateReadingLookalikes: (date: CalendarDate, corrected: Bool)? {
        if let date = lastDate { return (date, false) }
        let pattern = try? Regex<(Substring, Substring, Substring, Substring)>(Self.lookalikeDate)
        guard let pattern, let match = matches(of: pattern).last else { return nil }
        let (_, day, month, year) = match.output
        let parts = [day, month, year].map { NIK.digits(from: String($0)) }
        guard let date = Self.date(Substring(parts[0].0), Int(parts[1].0), Substring(parts[2].0)) else { return nil }
        return (date, parts.contains { $0.corrected })
    }

    /// dd-mm-yyyy where any digit may be a letter the NIK reads as one, built from `NIK.lookalikes` so the
    /// two lists can't drift apart. A pattern, not a Regex: a Regex isn't Sendable, so it can't be a static.
    private static let lookalikeDate: String = {
        let digit = "[0-9" + NSRegularExpression.escapedPattern(for: String(NIK.lookalikes.keys.sorted())) + "]"
        return "(\(digit){2})[-./](\(digit){2})[-./](\(digit){4})"
    }()

    /// Every dd-mm-yyyy in the text, with -, . or / between. Dates that can't exist are left out.
    var numericDates: [CalendarDate] {
        matches(of: /(\d{2})[-.\/](\d{2})[-.\/](\d{4})/).compactMap { match in
            let (_, day, month, year) = match.output
            return Self.date(day, Int(month), year)
        }
    }

    private static func date(_ day: Substring, _ month: Int?, _ year: Substring) -> CalendarDate? {
        guard let day = Int(day), let month, let year = Int(year) else { return nil }
        return CalendarDate(year: year, month: month, day: day)
    }

    private static let monthNumbers: [String: Int] = [
        "JANUARI": 1, "JANUARY": 1, "FEBRUARI": 2, "FEBRUARY": 2, "MARET": 3, "MARCH": 3, "APRIL": 4, "MEI": 5,
        "MAY": 5, "JUNI": 6, "JUNE": 6, "JULI": 7, "JULY": 7, "AGUSTUS": 8, "AUGUST": 8, "SEPTEMBER": 9,
        "OKTOBER": 10, "OCTOBER": 10, "NOVEMBER": 11, "DESEMBER": 12, "DECEMBER": 12,
    ]

    /// Names are printed in capitals, so anything else (a digit, a small letter, a separator left from
    /// the label) is a misread.
    var looksLikeAName: Bool {
        guard let first, ("A"..."Z").contains(first) else { return false }
        return allSatisfy { ("A"..."Z").contains($0) || " .,'-".contains($0) }
    }
}

extension Character {
    var isASCIIDigit: Bool { ("0"..."9").contains(self) }
}
