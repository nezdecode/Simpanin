//
//  PurgeCountdownTests.swift
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

@Suite("Purge countdown")
struct PurgeCountdownTests {
    // MARK: Baru dihapus counts down to the purge

    @Test func daysUntilPurge() {
        let deleted = Date(timeIntervalSince1970: 1_790_000_000)
        let day: TimeInterval = 86_400
        #expect(PurgeCountdown.daysLeft(deletedAt: deleted, now: deleted) == 30)
        #expect(PurgeCountdown.daysLeft(deletedAt: deleted, now: deleted + 7 * day) == 23)
        #expect(PurgeCountdown.daysLeft(deletedAt: deleted, now: deleted + 7 * day + 60) == 23)
        #expect(PurgeCountdown.daysLeft(deletedAt: deleted, now: deleted + 30 * day - 60) == 1)
        #expect(PurgeCountdown.daysLeft(deletedAt: deleted, now: deleted + 31 * day) == 0)
        #expect(String(localized: PurgeCountdown.text(daysLeft: 23)) == "Dihapus permanen dalam 23 hari")
        #expect(String(localized: PurgeCountdown.text(daysLeft: 0)) == "Dihapus permanen hari ini")
    }

    @Test func noticeCountsDownToThePurge() {
        #expect(
            String(localized: PurgeCountdown.notice(daysLeft: 29))
                == "Dihapus permanen dalam 29 hari. Pulihkan dulu untuk menyalin nomornya.")
        #expect(
            String(localized: PurgeCountdown.notice(daysLeft: 0))
                == "Dihapus permanen hari ini. Pulihkan dulu untuk menyalin nomornya.")
    }
}
