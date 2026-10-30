//
//  RecentlyDeletedView.swift
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

/// Baru dihapus: documents waiting for their purge, with the days left.
struct RecentlyDeletedView: View {
    let library: LibraryModel
    let documentScreen: (VaultCore.Document) -> DocumentDetailView
    /// A destination of its own rather than a value link: this screen is pushed by a view, and a value
    /// appended to the stack's path would land underneath it.
    @State private var opened: VaultCore.Document?

    var body: some View {
        Group {
            if library.loadFailed {
                ScrollView {
                    LoadFailedView { Task { await library.reload() } }
                        .padding(.top, 80)
                }
                .background(Color(.systemGroupedBackground))
            } else {
                List {
                    Section {
                        if library.deleted.isEmpty {
                            Text("list.recentlyDeletedEmpty").foregroundStyle(.secondary)
                        }
                        ForEach(library.deleted) { document in
                            DeletedDocumentRow(document: document) {
                                opened = document
                            } onRestore: {
                                Task { await library.restore(document.id) }
                            }
                        }
                    } footer: {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("deleted.explanation")
                            if !library.deleted.isEmpty { Text("deleted.openHint") }
                        }
                    }
                }
            }
        }
        .navigationTitle(Text("list.recentlyDeleted"))
        .navigationDestination(item: $opened, destination: documentScreen)
    }
}
