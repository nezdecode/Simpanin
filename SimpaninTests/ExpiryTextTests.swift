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
        for type in DocumentType.simClasses + [.sim, .stnk, .passport] {
            #expect(text(type, nil) == "Masa berlaku belum diisi", "\(type.rawValue)")
        }
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

    /// The banner on the list: documents that expire within 60 days or already have, soonest first.
    @Test func expiringSoonestFirst() {
        let soon = CalendarDate(year: 2026, month: 11, day: 1)!
        let later = CalendarDate(year: 2026, month: 12, day: 1)!
        let far = CalendarDate(year: 2030, month: 1, day: 1)!
        let past = CalendarDate(year: 2026, month: 1, day: 1)!
        // Indices into the input, past expiry first, then the soonest. Far and no expiry stay out.
        #expect(ExpiryText.needsAttention([later, nil, far, soon, past], today: today) == [4, 3, 0])
    }
}
