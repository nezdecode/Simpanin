//
//  RecentlyDeletedView.swift
//  Simpanin
//
//  Created by Inez Amanda on 15/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI
import VaultCore

/// Baru dihapus: documents waiting for their purge, with the days left.
struct RecentlyDeletedView: View {
    let library: LibraryModel

    var body: some View {
        List {
            Section {
                if library.deleted.isEmpty {
                    Text("list.recentlyDeletedEmpty").foregroundStyle(.secondary)
                }
                ForEach(library.deleted) { document in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(DocumentStyle.name(document.type, label: document.label)).font(.headline)
                        if let deletedAt = document.deletedAt {
                            Text(
                                PurgeCountdown.text(daysLeft: PurgeCountdown.daysLeft(deletedAt: deletedAt, now: .now))
                            )
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("document.row")
                    .swipeActions {
                        Button {
                            Task { await library.restore(document.id) }
                        } label: {
                            Text("button.restore")
                        }
                        .tint(.accentColor)
                    }
                }
            } footer: {
                Text("deleted.explanation")
            }
        }
        .navigationTitle(Text("list.recentlyDeleted"))
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
