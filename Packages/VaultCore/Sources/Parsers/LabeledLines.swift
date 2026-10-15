//
//  LabeledLines.swift
//  Parsers
//
//  Created by Inez Amanda on 15/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

/// Recognised lines read by their labels. A line that is itself one of the labels is never taken as
/// a value: recognition can return the label column before the value column.
struct LabeledLines {
    var lines: [String]
    /// Every label on the document, not only the ones read.
    var labels: [String]

    struct Found {
        var text: String
        /// The value sat on the line after its label, so which line belongs to it is a guess.
        var fromNextLine = false
        /// The line after the value isn't a label, so the value may go on there.
        var continues = false
    }

    func contains(_ label: String) -> Bool {
        lines.contains { Self.rest(after: label, in: $0) != nil }
    }

    /// The text after a label, from "Label : value" or from the line after a label on its own.
    func value(of wanted: String) -> Found? {
        for (index, line) in lines.enumerated() {
            guard let rest = Self.rest(after: wanted, in: line) else { continue }
            let next = index + 1 < lines.count ? lines[index + 1] : nil
            let nextIsLabel = next.map(isLabel) ?? true
            if !rest.isEmpty { return Found(text: rest, continues: !nextIsLabel) }
            guard let next, !nextIsLabel else { return nil }
            let afterNext = index + 2 < lines.count ? lines[index + 2] : nil
            var text = Substring(next.trimmingCharacters(in: .whitespaces))
            if text.first == ":" || text.first == ";" { text = text.dropFirst() }
            let value = text.trimmingCharacters(in: .whitespaces)
            let continues = afterNext.map { !isLabel($0) } ?? false
            return value.isEmpty ? nil : Found(text: value, fromNextLine: true, continues: continues)
        }
        return nil
    }

    private func isLabel(_ line: String) -> Bool {
        labels.contains { Self.rest(after: $0, in: line) != nil }
    }

    /// The rest of the line when it starts with the label, or nil. Recognition drops and adds spaces
    /// and dots, and reads the colon as a semicolon or drops it, so all of those are allowed.
    static func rest(after label: String, in line: String) -> String? {
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
}
