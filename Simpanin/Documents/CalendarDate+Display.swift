//
//  CalendarDate+Display.swift
//  Simpanin
//
//  Created by Inez Amanda on 14/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import VaultCore

extension CalendarDate {
    nonisolated var components: DateComponents { DateComponents(year: year, month: month, day: day) }

    /// Midnight UTC on this day, for a date picker that shows UTC.
    nonisolated var utcDate: Date? { Calendar.gregorianUTC.date(from: components) }

    /// The day a UTC date falls on.
    nonisolated init?(utc date: Date) {
        let parts = Calendar.gregorianUTC.dateComponents([.year, .month, .day], from: date)
        guard let year = parts.year, let month = parts.month, let day = parts.day else { return nil }
        self.init(year: year, month: month, day: day)
    }

    /// The day a moment falls on in a calendar, the phone's own for "today".
    nonisolated static func day(of date: Date, in calendar: Calendar) -> CalendarDate {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return CalendarDate(year: parts.year ?? 2000, month: parts.month ?? 1, day: parts.day ?? 1)
            ?? CalendarDate(year: 2000, month: 1, day: 1)!
    }

    /// Today on the phone's calendar.
    nonisolated static var today: CalendarDate { day(of: .now, in: .current) }

    /// The day in Indonesian, for example "17 Agu 2030". Read as UTC, so no time zone moves it.
    nonisolated var displayText: String {
        guard let date = Calendar.gregorianUTC.date(from: components) else { return string }
        return date.formatted(.indonesianDate(timeZone: .gmt))
    }

    /// The day and month in Indonesian, for example "3 Mar".
    nonisolated var dayAndMonthText: String {
        guard let date = Calendar.gregorianUTC.date(from: components) else { return string }
        return date.formatted(.indonesianDayMonth(timeZone: .gmt))
    }
}
