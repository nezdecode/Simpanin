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
                .onChange(of: autoLock) { _, choice in lock.setAutoLock(choice) }
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

extension Bundle {
    var shortVersion: String {
        object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }
}
