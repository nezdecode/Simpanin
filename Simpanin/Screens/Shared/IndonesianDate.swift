//
//  IndonesianDate.swift
//  Simpanin
//
//  Created by Inez Amanda on 15/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

/// Dates the way Simpanin shows them, in Indonesian: "14 Okt 2026", "3 Mar", "09.12".
nonisolated enum IndonesianDate {
    static let locale = Locale(identifier: "id_ID")

    /// Gregorian in UTC, for calendar days that no time zone may move.
    static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }()

    static func dayMonthYear(_ date: Date, timeZone: TimeZone) -> String {
        var style = Date.FormatStyle(locale: locale).day().month(.abbreviated).year()
        style.timeZone = timeZone
        return date.formatted(style)
    }

    static func dayMonth(_ date: Date, timeZone: TimeZone) -> String {
        var style = Date.FormatStyle(locale: locale).day().month(.abbreviated)
        style.timeZone = timeZone
        return date.formatted(style)
    }

    /// 24-hour time with a dot, as Indonesian writes it.
    static func time(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH.mm"
        return formatter.string(from: date)
    }
}
