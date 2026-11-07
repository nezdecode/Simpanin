//
//  DeletedDocumentActions.swift
//  Simpanin
//
//  Created by Inez Amanda on 7/11/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

/// Pulihkan and Hapus permanen under a document opened from Baru dihapus. Hapus permanen asks first.
struct DeletedDocumentActions: View {
    let onRestore: () -> Void
    let onDeletePermanently: () -> Void
    @State private var purgeAsked = false

    var body: some View {
        Section {
            Button(action: onRestore) {
                Text("button.restore")
            }
            .buttonStyle(.prominent)
            .accessibilityIdentifier("detail.restore")
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }
        Section {
            Button(role: .destructive) {
                purgeAsked = true
            } label: {
                Text("button.deletePermanently")
            }
            .accessibilityIdentifier("detail.deletePermanently")
        }
        .alert(Text("detail.deletePermanentlyTitle"), isPresented: $purgeAsked) {
            Button(role: .destructive, action: onDeletePermanently) {
                Text("button.deletePermanently")
            }
            Button(role: .cancel) {
            } label: {
                Text(ScreenText.cancel)
            }
        } message: {
            Text("detail.deletePermanentlyMessage")
        }
    }
}
