//
//  Calendar+UTC.swift
//  Simpanin
//
//  Created by Inez Amanda on 15/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

extension Calendar {
    /// Gregorian in UTC, for calendar days that no time zone may move.
    nonisolated static let gregorianUTC: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }()

    /// `gregorianUTC` for a date picker, which also starts its weeks on the day the phone's calendar does.
    nonisolated static var gregorianUTCPicker: Calendar {
        var calendar = gregorianUTC
        calendar.firstWeekday = Calendar.current.firstWeekday
        return calendar
    }
}
