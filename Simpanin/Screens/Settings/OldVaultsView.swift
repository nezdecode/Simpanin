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
                    HStack(spacing: 12) {
                        IconBadge(
                            symbol: "archivebox", tint: .secondary, background: Color(.systemGray5),
                            outline: .rounded(8))
                        VStack(alignment: .leading, spacing: 2) {
                            if let moved = OldVaultText.movedAt(folderName: old.folder.lastPathComponent) {
                                Text(OldVaultText.title(moved))
                                Text(OldVaultText.detail(moved, sizeInBytes: old.sizeInBytes))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text(verbatim: OldVaultsModel.sizeText(old.sizeInBytes))
                            }
                        }
                        Spacer(minLength: 0)
                        Button(role: .destructive) {
                            pendingDelete = old
                        } label: {
                            Text("button.delete")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(Color(.destructive))
                        .accessibilityIdentifier("oldVaults.delete")
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            pendingDelete = old
                        } label: {
                            Text("button.delete")
                        }
                    }
                }
                ForEach(model.unreadable, id: \.folder) { folder in
                    HStack(spacing: 12) {
                        IconBadge(
                            symbol: "exclamationmark.triangle", tint: Color(.onWarning), background: Color(.warning),
                            outline: .rounded(8))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("oldVaults.unreadableTitle")
                            Text(
                                OldVaultText.unreadableDetail(
                                    folderName: folder.folder.lastPathComponent, sizeInBytes: folder.sizeInBytes)
                            )
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("oldVaults.unreadable")
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
