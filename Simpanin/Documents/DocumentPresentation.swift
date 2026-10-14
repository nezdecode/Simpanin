//
//  DocumentPresentation.swift
//  Simpanin
//
//  Created by Inez Amanda on 15/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import DeveloperToolsSupport
import Foundation
import VaultCore

extension DocumentType {
    nonisolated static let simA = DocumentType(rawValue: "sim-a")
    nonisolated static let simB1 = DocumentType(rawValue: "sim-b1")
    nonisolated static let simB2 = DocumentType(rawValue: "sim-b2")
    nonisolated static let simC = DocumentType(rawValue: "sim-c")
    nonisolated static let simD = DocumentType(rawValue: "sim-d")
}

/// A type's name and tile colours. The colours only help tell types apart; the name is always
/// shown too.
nonisolated enum DocumentStyle {
    private static let nameKeys: [DocumentType: String] = [
        .ktp: "type.ktp", .simA: "type.simA", .simB1: "type.simB1", .simB2: "type.simB2", .simC: "type.simC",
        .simD: "type.simD", .sim: "type.sim", .passport: "type.passport", .stnk: "type.stnk", .kk: "type.kk",
        .npwp: "type.npwp", .bpjs: "type.bpjs",
    ]

    /// A type this build doesn't know, for example from a newer version, reads as "Lainnya".
    static func name(_ type: DocumentType) -> LocalizedStringResource {
        LocalizedStringResource(String.LocalizationValue(nameKeys[type] ?? "type.other"))
    }

    /// "NPWP · Kantor" for one-line rows. A blank label counts as none.
    static func name(_ type: DocumentType, label: String?) -> LocalizedStringResource {
        guard let label = shownLabel(label) else { return name(type) }
        return "type.withLabel \(String(localized: name(type))) \(label)"
    }

    static func shownLabel(_ label: String?) -> String? {
        guard let trimmed = label?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    /// Asset catalog colours, each with a light and a dark variant.
    @MainActor static func tileColours(_ type: DocumentType) -> (background: ColorResource, foreground: ColorResource) {
        switch type {
        case .ktp: (.tileKTPBackground, .tileKTPForeground)
        case .sim, .simA, .simB1, .simB2, .simC, .simD: (.tileSIMBackground, .tileSIMForeground)
        case .passport: (.tilePassportBackground, .tilePassportForeground)
        case .stnk: (.tileSTNKBackground, .tileSTNKForeground)
        case .kk: (.tileKKBackground, .tileKKForeground)
        case .npwp: (.tileNPWPBackground, .tileNPWPForeground)
        case .bpjs: (.tileBPJSBackground, .tileBPJSForeground)
        default: (.tileOtherBackground, .tileOtherForeground)
        }
    }
}

/// How an expiry date reads. Works on calendar days, so a time zone change never moves it.
nonisolated enum ExpiryText {
    /// Documents that expire within this many days get the warning.
    static let soonWindow = 60

    static func text(type: DocumentType, expiry: CalendarDate?, today: CalendarDate) -> LocalizedStringResource {
        guard let expiry else { return type == .ktp ? "expiry.lifetime" : "expiry.none" }
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
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        guard let startDate = calendar.date(from: start.components), let endDate = calendar.date(from: end.components)
        else { return 0 }
        return calendar.dateComponents([.day], from: startDate, to: endDate).day ?? 0
    }

    /// "3 Mar" this year, "3 Mar 2025" another year.
    private static func shortDate(_ date: CalendarDate, today: CalendarDate) -> String {
        date.year == today.year ? date.dayAndMonthText : date.displayText
    }
}

extension CalendarDate {
    nonisolated var components: DateComponents { DateComponents(year: year, month: month, day: day) }

    /// Today on the phone's calendar.
    nonisolated static var today: CalendarDate {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: .now)
        return CalendarDate(year: parts.year ?? 2000, month: parts.month ?? 1, day: parts.day ?? 1)
            ?? CalendarDate(year: 2000, month: 1, day: 1)!
    }

    /// The day in Indonesian, for example "17 Agu 2030". Read as UTC, so no time zone moves it.
    nonisolated var displayText: String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        guard let date = calendar.date(from: components) else { return string }
        var style = Date.FormatStyle(date: .abbreviated, time: .omitted, locale: Locale(identifier: "id_ID"))
        style.timeZone = .gmt
        return date.formatted(style)
    }

    /// The day and month in Indonesian, for example "3 Mar".
    nonisolated var dayAndMonthText: String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        guard let date = calendar.date(from: components) else { return string }
        var style = Date.FormatStyle(locale: Locale(identifier: "id_ID")).day().month(.abbreviated)
        style.timeZone = .gmt
        return date.formatted(style)
    }
}
