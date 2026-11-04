//
//  SharePurpose.swift
//  Simpanin
//
//  Created by Inez Amanda on 4/11/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

/// What the user types as Keperluan, and the mark made from it.
nonisolated enum SharePurpose {
    /// Short enough that the mark mostly fits on one line, so it covers less of the page.
    static let maxLength = 40

    /// On one line: control characters gone, any run of spaces or line breaks one space, trimmed, and at
    /// most `maxLength` characters.
    static func cleaned(_ text: String) -> String {
        var result = String.UnicodeScalarView()
        var pendingSpace = false
        for scalar in text.unicodeScalars {
            if scalar.properties.isWhitespace {
                pendingSpace = !result.isEmpty
                continue
            }
            switch scalar.properties.generalCategory {
            // The joiner holds emoji like a family together, so it stays.
            case .control,
                .format where scalar != "\u{200D}":
                continue
            default: break
            }
            if pendingSpace { result.append(" ") }
            pendingSpace = false
            result.append(scalar)
        }
        return String(String(result).prefix(maxLength)).trimmingCharacters(in: .whitespaces)
    }

    /// What the field keeps while typing.
    static func limited(_ text: String) -> String { String(text.prefix(maxLength)) }

    /// A copy always carries a purpose.
    static func canShare(_ text: String) -> Bool {
        !cleaned(text).isEmpty
    }

    /// "Sewa kos Jl. Perintis · 4 Nov 2026", as typed, never uppercased.
    static func mark(purpose: String, date: Date, timeZone: TimeZone) -> String {
        "\(cleaned(purpose)) · \(date.formatted(.indonesianDate(timeZone: timeZone)))"
    }
}
