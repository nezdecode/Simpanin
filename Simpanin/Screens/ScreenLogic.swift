//
//  ScreenLogic.swift
//  Simpanin
//
//  Created by Inez Amanda on 15/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import VaultCore

/// The texts of a "Data lama" entry. VaultCore names each folder after the moment it was moved
/// aside, in UTC (`yyyyMMdd-HHmmss`, plus "-2", "-3" when the name was taken).
nonisolated enum OldVaultText {
    static func movedAt(folderName: String) -> Date? {
        let stamp = String(folderName.prefix(15))
        guard stamp.count == 15 else { return nil }
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = .gmt
        parser.dateFormat = "yyyyMMdd-HHmmss"
        return parser.date(from: stamp)
    }

    static func title(_ movedAt: Date, timeZone: TimeZone = .current) -> LocalizedStringResource {
        var style = Date.FormatStyle(locale: Locale(identifier: "id_ID")).day().month(.abbreviated).year()
        style.timeZone = timeZone
        return "oldVaults.title \(movedAt.formatted(style))"
    }

    /// "12 MB · 2 Okt 2026", or only the size when the folder name has no date.
    static func unreadableDetail(
        folderName: String, sizeInBytes: Int64, timeZone: TimeZone = .current
    ) -> LocalizedStringResource {
        let size = OldVaultsModel.sizeText(sizeInBytes)
        guard let moved = movedAt(folderName: folderName) else { return "oldVaults.sizeOnly \(size)" }
        var style = Date.FormatStyle(locale: Locale(identifier: "id_ID")).day().month(.abbreviated).year()
        style.timeZone = timeZone
        return "oldVaults.unreadableDetail \(size) \(moved.formatted(style))"
    }

    static func detail(_ movedAt: Date, sizeInBytes: Int64, timeZone: TimeZone = .current) -> LocalizedStringResource {
        let time = DateFormatter()
        time.locale = Locale(identifier: "id_ID")
        time.timeZone = timeZone
        time.dateFormat = "HH.mm"
        return "oldVaults.detail \(OldVaultsModel.sizeText(sizeInBytes)) \(time.string(from: movedAt))"
    }
}

/// How long a document stays in Baru dihapus before VaultCore purges it.
nonisolated enum PurgeCountdown {
    static func daysLeft(deletedAt: Date, now: Date) -> Int {
        let remaining = deletedAt.addingTimeInterval(VaultStore.purgeDelay).timeIntervalSince(now)
        return max(0, Int((remaining / 86_400).rounded(.up)))
    }

    static func text(daysLeft: Int) -> LocalizedStringResource {
        daysLeft == 0 ? "deleted.purgeToday" : "deleted.purgeIn \(daysLeft)"
    }
}

/// "Kunci otomatis": how long the vault may stay open in the background. Five minutes at most,
/// because a longer time makes the lock weaker.
nonisolated enum AutoLock: String, CaseIterable, Sendable {
    case immediately, oneMinute, fiveMinutes

    private static let key = "autoLock"

    var seconds: TimeInterval {
        switch self {
        case .immediately: 0
        case .oneMinute: 60
        case .fiveMinutes: 300
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .immediately: "autoLock.immediately"
        case .oneMinute: "autoLock.oneMinute"
        case .fiveMinutes: "autoLock.fiveMinutes"
        }
    }

    static func stored(in defaults: UserDefaults = .standard) -> AutoLock {
        defaults.string(forKey: key).flatMap(AutoLock.init(rawValue:)) ?? .oneMinute
    }

    func store(in defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.key)
    }
}
