//
//  Date+Indonesian.swift
//  Simpanin
//
//  Created by Inez Amanda on 15/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

/// Dates the way Simpanin shows them, in Indonesian: "14 Okt 2026", "14 Okt", "09.12".
extension FormatStyle where Self == Date.FormatStyle {
    nonisolated static func indonesianDate(timeZone: TimeZone) -> Date.FormatStyle {
        indonesian(timeZone).day().month(.abbreviated).year()
    }

    nonisolated static func indonesianDayMonth(timeZone: TimeZone) -> Date.FormatStyle {
        indonesian(timeZone).day().month(.abbreviated)
    }

    /// 24-hour time; Indonesian writes it with a dot.
    nonisolated static func indonesianTime(timeZone: TimeZone) -> Date.FormatStyle {
        indonesian(timeZone).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
    }

    nonisolated private static func indonesian(_ timeZone: TimeZone) -> Date.FormatStyle {
        Date.FormatStyle(locale: Locale(identifier: "id_ID"), timeZone: timeZone)
    }
}

extension Calendar {
    /// Gregorian in UTC, for calendar days that no time zone may move.
    nonisolated static let gregorianUTC: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }()
}
