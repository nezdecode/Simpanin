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

    // MARK: Berlaku on the document screen

    struct Lines: Equatable {
        let title: String
        let value: String
        var status: String?
        var isExpired = false
    }

    func validity(_ type: DocumentType, _ expiry: CalendarDate?) -> Lines {
        let validity = ExpiryText.validity(type: type, expiry: expiry, today: today)
        let value =
            switch validity.value {
            case .date(let date): date.displayText
            case .phrase(let phrase): String(localized: phrase)
            }
        return Lines(
            title: String(localized: validity.title), value: value,
            status: validity.status.map { String(localized: $0.text) }, isExpired: validity.status?.isExpired ?? false)
    }

    @Test func berlakuShowsTheFullDateAndAStatusLine() {
        #expect(
            validity(.simA, day(45))
                == Lines(title: "Berlaku sampai", value: "29 Nov 2026", status: "Habis dalam 45 hari"))
        #expect(
            validity(.passport, CalendarDate(year: 2033, month: 8, day: 17))
                == Lines(title: "Berlaku sampai", value: "17 Agu 2033"))
    }

    /// The tile leaves this year out; the screen always says it.
    @Test func expiredShowsTheYear() {
        let expired = CalendarDate(year: 2026, month: 3, day: 3)
        let lines = Lines(
            title: "Berlaku sampai", value: "3 Mar 2026", status: "Sudah habis sejak 3 Mar 2026", isExpired: true)
        #expect(validity(.simA, expired) == lines)
    }

    @Test func todaySaysHabisHariIni() {
        let lines = Lines(title: "Berlaku sampai", value: "15 Okt 2026", status: "Habis hari ini")
        #expect(validity(.simA, today) == lines)
        #expect(validity(.stnk, today).status == "Pajak habis hari ini")
        #expect(!validity(.stnk, today).isExpired)
    }

    @Test(arguments: [-1, 0, 1, 60])
    func statusLineFromZeroToSixtyDays(_ offset: Int) {
        #expect(validity(.simC, day(offset)).status != nil)
        #expect(validity(.simC, day(offset)).isExpired == (offset < 0))
    }

    @Test func noStatusLineFromSixtyOneDays() {
        #expect(validity(.simC, day(61)) == Lines(title: "Berlaku sampai", value: "15 Des 2026"))
    }

    @Test func ktpIsSeumurHidup() {
        #expect(validity(.ktp, nil) == Lines(title: "Berlaku", value: "Seumur hidup"))
    }

    @Test(arguments: [DocumentType.kk, .npwp, .bpjs])
    func kkNPWPBPJSHaveNoExpiry(_ type: DocumentType) {
        #expect(validity(type, nil) == Lines(title: "Berlaku", value: "Tanpa masa berlaku"))
    }

    @Test func stnkSaysPajak() {
        #expect(
            validity(.stnk, day(45))
                == Lines(title: "Pajak berlaku sampai", value: "29 Nov 2026", status: "Pajak habis dalam 45 hari"))
        #expect(
            validity(.stnk, CalendarDate(year: 2025, month: 3, day: 3))
                == Lines(
                    title: "Pajak berlaku sampai", value: "3 Mar 2025", status: "Pajak sudah habis sejak 3 Mar 2025",
                    isExpired: true))
    }

    /// As on the tiles: a type that prints an expiry never claims to have none.
    @Test func emptyExpirySaysBelumDiisi() {
        for type in DocumentType.simClasses + [.sim, .passport] {
            #expect(
                validity(type, nil) == Lines(title: "Berlaku sampai", value: "Masa berlaku belum diisi"),
                "\(type.rawValue)")
        }
        #expect(validity(.stnk, nil) == Lines(title: "Pajak berlaku sampai", value: "Tanggal pajak belum diisi"))
    }

    @Test(arguments: [DocumentType.other, DocumentType(rawValue: "visa")])
    func otherAndUnknownTypesFollowTheirTile(_ type: DocumentType) {
        #expect(validity(type, nil) == Lines(title: "Berlaku", value: "Tanpa masa berlaku"))
        let soon = Lines(title: "Berlaku sampai", value: "29 Nov 2026", status: "Habis dalam 45 hari")
        #expect(validity(type, day(45)) == soon)
        #expect(validity(type, day(61)) == Lines(title: "Berlaku sampai", value: "15 Des 2026"))
    }

    /// A stored date reads the same on the screen as on the tile, whatever the type, so the two never
    /// disagree (only the DEBUG sample KTP has one today).
    @Test(arguments: [DocumentType.ktp, .kk, .simA, .stnk, .other])
    func aStoredDateFollowsTheTileRule(_ type: DocumentType) {
        for offset in [0, 45] {
            #expect(validity(type, day(offset)).status == text(type, day(offset)), "\(type.rawValue) \(offset)")
        }
        let far = validity(type, day(61))
        #expect(far.status == nil)
        #expect(far.value == day(61).displayText)
        #expect(text(type, day(61)).hasSuffix(far.value))
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
