//
//  PurgeCountdown.swift
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

/// How long a document stays in Baru dihapus before VaultCore purges it.
nonisolated enum PurgeCountdown {
    static func daysLeft(deletedAt: Date, now: Date) -> Int {
        let remaining = deletedAt.addingTimeInterval(VaultStore.purgeDelay).timeIntervalSince(now)
        return max(0, Int((remaining / 86_400).rounded(.up)))
    }

    static func text(daysLeft: Int) -> LocalizedStringResource {
        daysLeft == 0 ? "deleted.purgeToday" : "deleted.purgeIn \(daysLeft)"
    }

    /// The deleted document's notice, from the same count as its row.
    static func notice(daysLeft: Int) -> LocalizedStringResource {
        daysLeft == 0 ? "deleted.noticeToday" : "deleted.noticeIn \(daysLeft)"
    }
}
