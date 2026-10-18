//
//  SettingsView.swift
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

struct SettingsView: View {
    let vault: AppVault
    let lock: LockController
    let library: LibraryModel
    /// Owned here and shared with Data lama, so the size and the list come from one place.
    @State private var oldVaults: OldVaultsModel

    init(vault: AppVault, lock: LockController, library: LibraryModel) {
        self.vault = vault
        self.lock = lock
        self.library = library
        _oldVaults = State(initialValue: OldVaultsModel(store: vault.store, folder: vault.locations.quarantine))
    }

    var body: some View {
        Form {
            Section {
                NavigationLink {
                    AutoLockView(lock: lock)
                } label: {
                    LabeledContent {
                        Text(lock.autoLock.title)
                    } label: {
                        Text("settings.autoLock")
                    }
                }
                .accessibilityIdentifier("settings.autoLock")
            } header: {
                Text("settings.security")
            }
            Section {
                NavigationLink {
                    RecentlyDeletedView(library: library)
                } label: {
                    LabeledContent {
                        // No count while the list can't load: a 0 would say the bin is empty.
                        if !library.loadFailed {
                            Text(library.deleted.count, format: .number)
                        }
                    } label: {
                        Text("list.recentlyDeleted")
                    }
                }
                .accessibilityIdentifier("settings.recentlyDeleted")
                NavigationLink {
                    OldVaultsView(model: oldVaults)
                } label: {
                    LabeledContent {
                        if !oldVaults.loadFailed, oldVaults.totalSizeInBytes > 0 {
                            Text(verbatim: oldVaults.totalSizeInBytes.formatted(.byteCount(style: .file)))
                        }
                    } label: {
                        Text("settings.oldVaults")
                    }
                }
                .accessibilityIdentifier("settings.oldVaults")
            } header: {
                Text("settings.data")
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
            // No Privasi heading until "Cara Simpanin melindungi dokumenmu" exists; a heading with
            // nothing under it would look broken.
            Section {
            } footer: {
                VStack(alignment: .leading, spacing: 16) {
                    Text("settings.deviceOnly")
                    Label {
                        Text("settings.noAccount \(Bundle.main.shortVersion)")
                    } icon: {
                        Image(systemName: "checkmark.shield").foregroundStyle(.tint)
                    }
                }
            }
        }
        .navigationTitle(Text("settings.title"))
        .task { await oldVaults.reload() }
    }
}

extension Bundle {
    var shortVersion: String {
        object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }
}
