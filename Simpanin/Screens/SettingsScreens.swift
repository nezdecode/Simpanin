//
//  SettingsScreens.swift
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
    let library: Library

    var body: some View {
        List {
            Section {
                if library.deleted.isEmpty {
                    Text("list.recentlyDeletedEmpty").foregroundStyle(.secondary)
                }
                ForEach(library.deleted) { document in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(DocumentStyle.name(document.type)).font(.headline)
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

struct SettingsView: View {
    let vault: AppVault
    let lock: LockController
    let library: Library
    @State private var autoLock = AutoLock.stored()

    var body: some View {
        Form {
            Section {
                Picker(selection: $autoLock) {
                    ForEach(AutoLock.allCases, id: \.self) { choice in
                        Text(choice.title).tag(choice)
                    }
                } label: {
                    Text("settings.autoLock")
                }
                .onChange(of: autoLock) { _, choice in
                    choice.store()
                    lock.relockTimeout = choice.seconds
                }
            } header: {
                Text("settings.security")
            }
            Section {
                NavigationLink {
                    RecentlyDeletedView(library: library)
                } label: {
                    LabeledContent {
                        Text(library.deleted.count, format: .number)
                    } label: {
                        Text("list.recentlyDeleted")
                    }
                }
                NavigationLink {
                    OldVaultsView(model: OldVaultsModel(store: vault.store, folder: vault.locations.quarantine))
                } label: {
                    Text("settings.oldVaults")
                }
                .accessibilityIdentifier("settings.oldVaults")
            } header: {
                Text("settings.data")
            }
            Section {
                Text("settings.deviceOnly")
                Text("settings.noAccount")
            } header: {
                Text("settings.privacy")
            } footer: {
                Text("settings.version \(Bundle.main.shortVersion)")
            }
            #if DEBUG
                Section {
                    NavigationLink {
                        DeviceChecksView(vault: vault, lock: lock)
                    } label: {
                        Text(verbatim: "Device checks")
                    }
                }
            #endif
        }
        .navigationTitle(Text("settings.title"))
    }
}

/// "Data lama": old vaults moved aside by "Mulai vault baru". Deleting one asks first, because it
/// also deletes the old vault's Keychain item.
struct OldVaultsView: View {
    @State var model: OldVaultsModel
    @State private var pendingDelete: QuarantinedVault?

    var body: some View {
        List {
            Section {
                if model.vaults.isEmpty {
                    Text("oldVaults.empty").foregroundStyle(.secondary)
                }
                ForEach(model.vaults, id: \.folder) { old in
                    VStack(alignment: .leading, spacing: 4) {
                        if let moved = OldVaultText.movedAt(folderName: old.folder.lastPathComponent) {
                            Text(OldVaultText.title(moved)).font(.headline)
                            Text(OldVaultText.detail(moved, sizeInBytes: old.sizeInBytes))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            Text(verbatim: OldVaultsModel.sizeText(old.sizeInBytes))
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            pendingDelete = old
                        } label: {
                            Text("button.delete")
                        }
                    }
                }
            } header: {
                Text("oldVaults.explanation").textCase(nil)
            } footer: {
                Text("oldVaults.footer")
            }
        }
        .navigationTitle(Text("settings.oldVaults"))
        .task { await model.reload() }
        .confirmationDialog(
            Text("oldVaults.deleteConfirm"),
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
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
