//
//  ExpiryText.swift
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

/// How an expiry date reads. Works on calendar days, so a time zone change never moves it.
nonisolated enum ExpiryText {
    /// Documents that expire within this many days get the warning.
    static let soonWindow = 60

    static func text(type: DocumentType, expiry: CalendarDate?, today: CalendarDate) -> LocalizedStringResource {
        guard let expiry else {
            if type == .ktp { return "expiry.lifetime" }
            // An STNK's date is its yearly tax, not the card's five-year validity.
            if type == .stnk { return "expiry.taxMissing" }
            // Read from the type and an empty date alone, as the list shows it without decrypting.
            return hasPrintedExpiry(type) ? "expiry.missing" : "expiry.none"
        }
        let left = days(from: today, to: expiry)
        let tax = type == .stnk
        switch left {
        case ..<0:
            let date = shortDate(expiry, today: today)
            return tax ? "expiry.taxExpired \(date)" : "expiry.expired \(date)"
        case 0:
            return tax ? "expiry.taxToday" : "expiry.today"
        case 1...soonWindow:
            return tax ? "expiry.taxSoon \(left)" : "expiry.soon \(left)"
        default:
            return tax ? "expiry.tax \(expiry.displayText)" : "expiry.valid \(expiry.displayText)"
        }
    }

    /// Types with a printed expiry; one saved without a date is missing it, not without one.
    static func hasPrintedExpiry(_ type: DocumentType) -> Bool {
        type.isSIM || type == .stnk || type == .passport
    }

    /// Indices of the documents that need attention, past expiry first, then the soonest.
    static func needsAttention(_ expiries: [CalendarDate?], today: CalendarDate) -> [Int] {
        expiries.enumerated()
            .compactMap { index, expiry -> (Int, CalendarDate)? in
                guard let expiry, days(from: today, to: expiry) <= soonWindow else { return nil }
                return (index, expiry)
            }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
    }

    static func days(from start: CalendarDate, to end: CalendarDate) -> Int {
        let calendar = Calendar.gregorianUTC
        guard let startDate = calendar.date(from: start.components), let endDate = calendar.date(from: end.components)
        else { return 0 }
        return calendar.dateComponents([.day], from: startDate, to: endDate).day ?? 0
    }

    /// "3 Mar" this year, "3 Mar 2025" another year.
    private static func shortDate(_ date: CalendarDate, today: CalendarDate) -> String {
        date.year == today.year ? date.dayAndMonthText : date.displayText
    }
}
