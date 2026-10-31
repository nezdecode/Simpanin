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

/// A document in Baru dihapus, with the days until it's purged. A tap opens it; a swipe, a long press or
/// VoiceOver's action restores it.
struct DeletedDocumentRow: View {
    let document: VaultCore.Document
    let onOpen: () -> Void
    let onRestore: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack {
                content
                Spacer(minLength: 0)
                DisclosureChevron()
            }
        }
        .foregroundStyle(.primary)
        .accessibilityIdentifier("document.row")
        .accessibilityAction(named: Text("button.restore"), onRestore)
        .contextMenu {
            Button(action: onRestore) {
                Label {
                    Text("button.restore")
                } icon: {
                    Image(systemName: "arrow.uturn.backward")
                }
            }
        }
        .swipeActions {
            Button {
                onRestore()
            } label: {
                Text("button.restore")
            }
            .tint(.accentColor)
        }
    }

    private var content: some View {
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
    }
}
