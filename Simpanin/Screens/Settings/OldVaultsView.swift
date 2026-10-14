//
//  OldVaultsView.swift
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

/// "Data lama": old vaults moved aside by "Mulai vault baru". Deleting one asks first, because it
/// also deletes the old vault's Keychain item.
struct OldVaultsView: View {
    @State var model: OldVaultsModel
    @State private var pendingDelete: QuarantinedVault?

    var body: some View {
        List {
            Section {
                if model.vaults.isEmpty && model.unreadable.isEmpty {
                    Text("oldVaults.empty").foregroundStyle(.secondary)
                }
                ForEach(model.vaults, id: \.folder) { old in
                    OldVaultRow(vault: old) { pendingDelete = old }
                }
                ForEach(model.unreadable, id: \.folder) { folder in
                    UnreadableFolderRow(folder: folder)
                }
            } header: {
                Text("oldVaults.explanation").textCase(nil)
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    if !model.vaults.isEmpty { Text("oldVaults.footer") }
                    if !model.unreadable.isEmpty { Text("oldVaults.unreadableFooter") }
                }
            }
        }
        .navigationTitle(Text("settings.oldVaults"))
        .task { await model.reload() }
        .confirmationDialog(
            Text("oldVaults.deleteConfirm"),
            isPresented: Binding(isPresent: $pendingDelete),
            titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                if let old = pendingDelete { Task { await model.delete(old) } }
                pendingDelete = nil
            } label: {
                Text("button.deleteForever")
            }
        } message: {
            Text("oldVaults.deleteMessage")
        }
    }
}
