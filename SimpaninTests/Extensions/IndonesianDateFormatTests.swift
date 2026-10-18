//
//  IndonesianDateFormatTests.swift
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

@testable import Simpanin

@Suite("Indonesian date formats")
struct IndonesianDateFormatTests {
    /// 14 Oct 2026, 02:12 UTC, which is 09.12 in Jakarta.
    let moment = Date(timeIntervalSince1970: 1_791_943_920)
    let jakarta = TimeZone(identifier: "Asia/Jakarta")!

    @Test func formats() {
        #expect(moment.formatted(.indonesianDate(timeZone: jakarta)) == "14 Okt 2026")
        #expect(moment.formatted(.indonesianDayMonth(timeZone: jakarta)) == "14 Okt")
        #expect(moment.formatted(.indonesianTime(timeZone: jakarta)) == "09.12")
    }

    @Test func theTimeZoneDecidesTheDay() {
        // 23:30 UTC on 13 Oct is already 14 Oct in Jakarta.
        let lateNight = Date(timeIntervalSince1970: 1_791_934_200)
        #expect(lateNight.formatted(.indonesianDate(timeZone: .gmt)) == "13 Okt 2026")
        #expect(lateNight.formatted(.indonesianDate(timeZone: jakarta)) == "14 Okt 2026")
    }

    @Test func gregorianUTC() {
        #expect(Calendar.gregorianUTC.identifier == .gregorian)
        #expect(Calendar.gregorianUTC.timeZone == .gmt)
    }
}
