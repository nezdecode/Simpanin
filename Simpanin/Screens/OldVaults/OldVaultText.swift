//
//  OldVaultText.swift
//  Simpanin
//
//  Created by Inez Amanda on 14/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

/// The texts of a "Data lama" entry. VaultCore names each folder after the moment it was moved
/// aside, in UTC (`yyyyMMdd-HHmmss`, plus "-2", "-3" when the name was taken).
nonisolated enum OldVaultText {
    /// VaultCore's fixed folder-name format, in UTC. Display goes through `.indonesianDate`.
    private static let folderNameDate = Date.ParseStrategy(
        format: """
            \(year: .padded(4))\(month: .twoDigits)\(day: .twoDigits)-\
            \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased))\(minute: .twoDigits)\(second: .twoDigits)
            """,
        timeZone: .gmt, isLenient: false)

    static func movedAt(folderName: String) -> Date? {
        let stamp = String(folderName.prefix(15))
        guard stamp.count == 15 else { return nil }
        return try? Date(stamp, strategy: folderNameDate)
    }

    static func title(_ movedAt: Date, timeZone: TimeZone = .current) -> LocalizedStringResource {
        "oldVaults.title \(movedAt.formatted(.indonesianDate(timeZone: timeZone)))"
    }

    /// "12 MB · 2 Okt 2026", or only the size when the folder name has no date.
    static func unreadableDetail(
        folderName: String, sizeInBytes: Int64, timeZone: TimeZone = .current
    ) -> LocalizedStringResource {
        let size = sizeInBytes.formatted(.byteCount(style: .file))
        guard let moved = movedAt(folderName: folderName) else { return "oldVaults.sizeOnly \(size)" }
        return "oldVaults.unreadableDetail \(size) \(moved.formatted(.indonesianDate(timeZone: timeZone)))"
    }

    static func detail(_ movedAt: Date, sizeInBytes: Int64, timeZone: TimeZone = .current) -> LocalizedStringResource {
        let time = movedAt.formatted(.indonesianTime(timeZone: timeZone))
        return "oldVaults.detail \(sizeInBytes.formatted(.byteCount(style: .file))) \(time)"
    }
}
