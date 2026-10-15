//
//  DeletedDocumentRow.swift
//  Simpanin
//
//  Created by Inez Amanda on 14/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI
import VaultCore

/// A document in Baru dihapus, with the days until it's purged. Swipe to restore.
struct DeletedDocumentRow: View {
    let document: Document
    let onRestore: () -> Void

    var body: some View {
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
                onRestore()
            } label: {
                Text("button.restore")
            }
            .tint(.accentColor)
        }
    }
}
