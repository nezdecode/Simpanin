//
//  ExpiryTextTests.swift
//  SimpaninTests
//
//  Created by Inez Amanda on 14/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import Testing
import VaultCore

@testable import Simpanin

/// How an expiry date reads, from the calendar days alone.
@Suite("Expiry wording")
struct ExpiryTextTests {
    let today = CalendarDate(year: 2026, month: 10, day: 15)!

    func text(_ type: DocumentType, _ expiry: CalendarDate?) -> String {
        String(localized: ExpiryText.text(type: type, expiry: expiry, today: today))
    }

    @Test func noExpiry() {
        #expect(text(.ktp, nil) == "Seumur hidup")
        #expect(text(.kk, nil) == "Tanpa masa berlaku")
        #expect(text(.bpjs, nil) == "Tanpa masa berlaku")
        #expect(text(.npwp, nil) == "Tanpa masa berlaku")
        #expect(text(.other, nil) == "Tanpa masa berlaku")
    }

    /// A type that does expire, saved without a date, says so; it never claims to have no expiry.
    @Test func aMissingExpiryIsNotNoExpiry() {
        for type in DocumentType.simClasses + [.sim, .passport] {
            #expect(text(type, nil) == "Masa berlaku belum diisi", "\(type.rawValue)")
        }
        // An STNK's date is its yearly tax, not the card's five-year validity.
        #expect(text(.stnk, nil) == "Tanggal pajak belum diisi")
    }

    @Test func validLongerThanSixtyDays() {
        #expect(text(.passport, CalendarDate(year: 2033, month: 8, day: 17)) == "Berlaku sampai 17 Agu 2033")
        #expect(text(.stnk, CalendarDate(year: 2027, month: 3, day: 3)) == "Pajak sampai 3 Mar 2027")
    }

    @Test func withinSixtyDays() {
        #expect(text(.simA, CalendarDate(year: 2026, month: 11, day: 29)) == "Habis dalam 45 hari")
        #expect(text(.simA, CalendarDate(year: 2026, month: 12, day: 14)) == "Habis dalam 60 hari")
        #expect(text(.simA, today) == "Habis hari ini")
        #expect(text(.stnk, CalendarDate(year: 2026, month: 11, day: 29)) == "Pajak habis dalam 45 hari")
    }

    @Test func pastExpiry() {
        #expect(text(.simA, CalendarDate(year: 2026, month: 3, day: 3)) == "Sudah habis sejak 3 Mar")
        #expect(text(.simA, CalendarDate(year: 2025, month: 3, day: 3)) == "Sudah habis sejak 3 Mar 2025")
        #expect(text(.stnk, CalendarDate(year: 2026, month: 10, day: 14)) == "Pajak sudah habis sejak 14 Okt")
    }

    func day(_ offset: Int) -> CalendarDate {
        CalendarDate(utc: today.utcDate!.addingTimeInterval(Double(offset) * 86_400))!
    }

    func candidate(_ offset: Int?, _ type: DocumentType = .simC, created: TimeInterval = 0)
        -> ExpiryText.BannerCandidate
    {
        ExpiryText.BannerCandidate(
            type: type, expiry: offset.map(day), createdAt: Date(timeIntervalSince1970: created))
    }

    func order(_ candidates: [ExpiryText.BannerCandidate]) -> [Int] {
        ExpiryText.bannerOrder(candidates, today: today)
    }

    // MARK: The banner's order (indices into the input)

    @Test func theNearestToTodayComesFirst() {
        #expect(order([candidate(30), candidate(-5), candidate(10)]) == [1, 2, 0])
    }

    @Test func recentlyExpiredComesBeforeLongExpired() {
        #expect(order([candidate(-200), candidate(-10)]) == [1, 0])
    }

    /// Nothing leaves the banner because time passed; only the user hides it.
    @Test func longExpiredStaysInTheBanner() {
        #expect(order([candidate(-1000)]) == [0])
    }

    @Test func farAheadOrUndatedIsLeftOut() {
        #expect(order([candidate(61), candidate(nil), candidate(200)]).isEmpty)
    }

    /// 60 days either side is near; on the same distance, the expired one comes first.
    @Test func theSixtyDayBoundaryIsInclusive() {
        #expect(order([candidate(60), candidate(-60), candidate(61), candidate(-61)]) == [1, 0, 3])
    }

    /// Same date: by type, then by when the document was made, so the banner never shuffles.
    @Test func sameDayDocumentsHaveAStableOrder() {
        let same = [
            candidate(10, .stnk, created: 2), candidate(10, .passport, created: 1),
            candidate(10, .passport, created: 0),
        ]
        #expect(order(same) == [2, 1, 0])
    }

    /// The day comes from the phone's own calendar: a minute before midnight is still today.
    @Test func theDayFollowsThePhonesCalendar() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Makassar"))
        let lastMinute = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 10, day: 15, hour: 23, minute: 59)))
        #expect(CalendarDate.day(of: lastMinute, in: calendar) == CalendarDate(year: 2026, month: 10, day: 15))
        #expect(
            CalendarDate.day(of: lastMinute.addingTimeInterval(60), in: calendar)
                == CalendarDate(year: 2026, month: 10, day: 16))
    }
}
