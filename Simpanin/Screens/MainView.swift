//
//  MainView.swift
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

/// The unlocked app: the document list, Recently deleted and Settings. Minimal on purpose,
/// so the wiring can be seen; the design comes later.
struct MainView: View {
    let vault: AppVault
    let lock: LockController
    @State private var library: Library

    init(vault: AppVault, lock: LockController) {
        self.vault = vault
        self.lock = lock
        _library = State(initialValue: Library(store: vault.store))
    }

    var body: some View {
        NavigationStack {
            List {
                if lock.notices.contains(.repairWaitingForSpace) {
                    Section {
                        Label {
                            Text(VaultNotice.repairWaitingForSpace.message)
                        } icon: {
                            Image(systemName: "externaldrive.badge.exclamationmark")
                        }
                        .swipeActions {
                            Button {
                                lock.dismiss(.repairWaitingForSpace)
                            } label: {
                                Text(ScreenText.okay)
                            }
                        }
                    }
                }
                Section {
                    if library.documents.isEmpty {
                        Text("list.empty").foregroundStyle(.secondary)
                    }
                    ForEach(library.documents) { document in
                        DocumentRow(document: document)
                            .swipeActions {
                                Button(role: .destructive) {
                                    Task { await library.delete(document.id) }
                                } label: {
                                    Text("button.delete")
                                }
                            }
                    }
                }
                Section {
                    NavigationLink {
                        RecentlyDeletedView(library: library)
                    } label: {
                        Text("list.recentlyDeleted")
                    }
                }
            }
            .navigationTitle(Text("list.title"))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Task { await lock.lock() }
                    } label: {
                        Text("button.lock")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView(vault: vault, lock: lock)
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
                #if DEBUG
                    ToolbarItem(placement: .bottomBar) {
                        Button {
                            Task { await library.addSample() }
                        } label: {
                            Text("debug.addSample")
                        }
                    }
                #endif
            }
            .task { await library.reload() }
            .alert(
                Text(RecoveryContent(.storageFullOnSave).message),
                isPresented: Binding(get: { library.saveError != nil }, set: { if !$0 { library.saveError = nil } })
            ) {
                Button {
                    library.saveError = nil
                } label: {
                    Text(ScreenText.okay)
                }
            }
            .alert(
                oneTimeNotice.map { Text($0.message) } ?? Text(verbatim: ""),
                isPresented: Binding(
                    get: { oneTimeNotice != nil }, set: { if !$0, let notice = oneTimeNotice { lock.dismiss(notice) } })
            ) {
                Button {
                    if let notice = oneTimeNotice { lock.dismiss(notice) }
                } label: {
                    Text(ScreenText.okay)
                }
            }
        }
    }

    /// The notices shown once as an alert. The full-disk one is a banner instead.
    private var oneTimeNotice: VaultNotice? {
        [VaultNotice.recoveredFromPages, .newestChangeMayBeLost].first { lock.notices.contains($0) }
    }
}

struct DocumentRow: View {
    let document: Document

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(document.type.displayName).font(.headline)
            if let expiry = document.expiry {
                Text("list.expiry \(expiry.displayText)").font(.subheadline).foregroundStyle(.secondary)
            } else {
                Text("list.noExpiry").font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}

struct RecentlyDeletedView: View {
    let library: Library

    var body: some View {
        List {
            if library.deleted.isEmpty {
                Text("list.recentlyDeletedEmpty").foregroundStyle(.secondary)
            }
            ForEach(library.deleted) { document in
                DocumentRow(document: document)
                    .swipeActions {
                        Button {
                            Task { await library.restore(document.id) }
                        } label: {
                            Text("button.restore")
                        }
                    }
            }
        }
        .navigationTitle(Text("list.recentlyDeleted"))
    }
}

struct SettingsView: View {
    let vault: AppVault
    let lock: LockController

    var body: some View {
        List {
            NavigationLink {
                OldVaultsView(model: OldVaultsModel(store: vault.store, folder: vault.locations.quarantine))
            } label: {
                Text("settings.oldVaults")
            }
            #if DEBUG
                NavigationLink {
                    DeviceChecksView(vault: vault, lock: lock)
                } label: {
                    Text(verbatim: "Device checks")
                }
            #endif
        }
        .navigationTitle(Text("settings.title"))
    }
}

/// "Data lama": old vaults with their size. Deleting asks first, because it also deletes the
/// old vault's Keychain item.
struct OldVaultsView: View {
    @State var model: OldVaultsModel
    @State private var pendingDelete: QuarantinedVault?

    var body: some View {
        List {
            if model.vaults.isEmpty {
                Text("oldVaults.empty").foregroundStyle(.secondary)
            }
            ForEach(model.vaults, id: \.folder) { old in
                Text("oldVaults.row \(OldVaultsModel.sizeText(old.sizeInBytes))")
                    .swipeActions {
                        Button(role: .destructive) {
                            pendingDelete = old
                        } label: {
                            Text("button.delete")
                        }
                    }
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
                Text("button.delete")
            }
        }
    }
}

extension DocumentType {
    var displayName: LocalizedStringResource {
        switch self {
        case .ktp: "type.ktp"
        case .kk: "type.kk"
        case .sim: "type.sim"
        case .stnk: "type.stnk"
        case .passport: "type.passport"
        case .npwp: "type.npwp"
        case .bpjs: "type.bpjs"
        default: "type.other"
        }
    }
}

extension CalendarDate {
    /// The day in Indonesian, for example "17 Agu 2030". Read as UTC, so no time zone moves it.
    var displayText: String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { return string }
        var style = Date.FormatStyle(date: .abbreviated, time: .omitted, locale: Locale(identifier: "id_ID"))
        style.timeZone = .gmt
        return date.formatted(style)
    }
}
