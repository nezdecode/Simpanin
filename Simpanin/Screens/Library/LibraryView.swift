//
//  LibraryView.swift
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

/// The unlocked app: the document list, Baru dihapus and Settings. The list shows only the type
/// and the expiry, never a name or a number: those stay sealed until a document is opened.
struct LibraryView: View {
    let vault: AppVault
    let lock: LockController
    @State private var library: LibraryModel
    @Environment(\.dynamicTypeSize) private var typeSize

    init(vault: AppVault, lock: LockController) {
        self.vault = vault
        self.lock = lock
        _library = State(initialValue: LibraryModel(store: Self.documentStore(for: vault)))
    }

    private var today: CalendarDate { CalendarDate.today }

    private static func documentStore(for vault: AppVault) -> any DocumentStoring {
        #if DEBUG
            if UITestSetup.isActive { return UITestSetup.documentStore(for: vault) }
        #endif
        return vault.store
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !library.loadFailed, !library.documents.isEmpty {
                        Label {
                            Text("main.subtitle \(library.documents.count)")
                        } icon: {
                            Image(systemName: "lock.shield").foregroundStyle(.tint)
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                    NoticeList(notices: lock.notices, onDismiss: lock.dismiss)
                    if library.loadFailed {
                        LoadFailedView { Task { await library.reload() } }
                            .padding(.top, 80)
                    } else {
                        if library.documents.isEmpty {
                            EmptyLibraryView()
                        } else {
                            ExpiryBanner(documents: library.documents, today: today)
                            Text("main.allDocuments").font(.title3.weight(.semibold)).padding(.top, 8)
                            LazyVGrid(columns: columns, spacing: 12) {
                                ForEach(library.documents) { document in
                                    DocumentTile(document: document, today: today, wide: typeSize.isAccessibilitySize)
                                        .contextMenu {
                                            Button(role: .destructive) {
                                                Task { await library.delete(document.id) }
                                            } label: {
                                                Label {
                                                    Text("button.delete")
                                                } icon: {
                                                    Image(systemName: "trash")
                                                }
                                            }
                                        }
                                }
                            }
                        }
                        NavigationLink {
                            RecentlyDeletedView(library: library)
                        } label: {
                            GroupedRow(
                                title: "list.recentlyDeleted", value: "\(library.deleted.count)", systemImage: "trash")
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("list.recentlyDeleted")
                        .padding(.top, 8)
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(Text("list.title"))
            .toolbar { toolbar }
            .task { await library.reload() }
            .alert(
                library.saveError.map { Text(RecoveryContent($0).message) } ?? Text(verbatim: ""),
                isPresented: Binding(isPresent: $library.saveError)
            ) {
                Button {
                    library.saveError = nil
                } label: {
                    Text(ScreenText.okay)
                }
            } message: {
                if library.saveError == .storageFullOnSave { Text("saveFull.hint") }
            }
        }
    }

    /// Two columns, or one at the accessibility text sizes, where two would not fit.
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12), count: typeSize.isAccessibilitySize ? 1 : 2)
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                Task { await lock.lock() }
            } label: {
                Label {
                    Text("main.lockNow")
                } icon: {
                    Image(systemName: "lock")
                }
            }
            .accessibilityIdentifier("list.lock")
        }
        ToolbarItem(placement: .topBarTrailing) {
            NavigationLink {
                SettingsView(vault: vault, lock: lock, library: library)
            } label: {
                Label {
                    Text("settings.title")
                } icon: {
                    Image(systemName: "gearshape")
                }
            }
            .accessibilityIdentifier("list.settings")
        }
        #if DEBUG
            // Scanning isn't built yet, so in DEBUG "+" adds a synthetic sample document.
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await library.addSample() }
                } label: {
                    Label {
                        Text("debug.addSample")
                    } icon: {
                        Image(systemName: "plus")
                    }
                }
                // Saving while the list can't load would only confuse; it can't harm the vault.
                .disabled(library.loadFailed)
                .accessibilityIdentifier("list.addSample")
            }
        #endif
    }
}
