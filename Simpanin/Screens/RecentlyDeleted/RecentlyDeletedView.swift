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
                    DeletedDocumentRow(document: document) { Task { await library.restore(document.id) } }
                }
            } footer: {
                Text("deleted.explanation")
            }
        }
        .navigationTitle(Text("list.recentlyDeleted"))
    }
}
