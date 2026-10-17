//
//  HiddenBanner.swift
//  Simpanin
//
//  Created by Inez Amanda on 17/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import VaultCore

/// The documents the user took out of the expiry banner with "Jangan tampilkan di sini", each with the
/// expiry date it had then, so a changed date brings it back.
nonisolated struct HiddenBanner: Codable, Equatable, Sendable {
    struct Entry: Codable, Equatable, Sendable {
        var id: DocumentID
        var expiry: CalendarDate
        /// Hidden when it had already expired. One hidden while still to come shows once more on expiring.
        var whileExpired: Bool
    }

    private(set) var entries: [Entry] = []

    func hides(_ id: DocumentID, expiry: CalendarDate?, today: CalendarDate) -> Bool {
        guard let expiry, let entry = entries.first(where: { $0.id == id }), entry.expiry == expiry else {
            return false
        }
        // "Habis dalam 5 hari" and "Sudah habis" are different news: expiring brings it back once.
        return entry.whileExpired || ExpiryText.days(from: today, to: expiry) >= 0
    }

    mutating func hide(_ id: DocumentID, expiry: CalendarDate, today: CalendarDate) {
        entries.removeAll { $0.id == id }
        entries.append(Entry(id: id, expiry: expiry, whileExpired: ExpiryText.days(from: today, to: expiry) < 0))
    }

    /// Drops entries for documents that no longer exist. True when any went.
    mutating func prune(keeping ids: Set<DocumentID>) -> Bool {
        let before = entries.count
        entries.removeAll { !ids.contains($0.id) }
        return entries.count != before
    }
}
