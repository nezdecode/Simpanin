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

/// The unlocked app: the document list, Baru dihapus and Settings. The list shows only the type
/// and the expiry, never a name or a number: those stay sealed until a document is opened.
struct MainView: View {
    let vault: AppVault
    let lock: LockController
    @State private var library: Library
    @Environment(\.dynamicTypeSize) private var typeSize

    init(vault: AppVault, lock: LockController) {
        self.vault = vault
        self.lock = lock
        _library = State(initialValue: Library(store: vault.store))
    }

    private var today: CalendarDate { CalendarDate.today }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !library.documents.isEmpty {
                        Label {
                            Text("main.subtitle \(library.documents.count)")
                        } icon: {
                            Image(systemName: "lock.shield").foregroundStyle(.tint)
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                    notices
                    if library.documents.isEmpty {
                        EmptyLibraryView()
                    } else {
                        expiryBanner
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
                        GroupedRow(title: "list.recentlyDeleted", value: "\(library.deleted.count)", symbol: "trash")
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("list.recentlyDeleted")
                    .padding(.top, 8)
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(Text("list.title"))
            .toolbar { toolbar }
            .task { await library.reload() }
            .alert(
                library.saveError.map { Text(RecoveryContent($0).message) } ?? Text(verbatim: ""),
                isPresented: Binding(get: { library.saveError != nil }, set: { if !$0 { library.saveError = nil } })
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
                .accessibilityIdentifier("list.addSample")
            }
        #endif
    }

    /// The one-time notices from opening, then the full-disk banner, each dismissed with "Oke".
    @ViewBuilder private var notices: some View {
        let order: [VaultNotice] = [.recoveredFromPages, .newestChangeMayBeLost, .repairWaitingForSpace]
        ForEach(order, id: \.self) { notice in
            if lock.notices.contains(notice) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: notice == .repairWaitingForSpace ? "externaldrive" : "info.circle")
                    VStack(alignment: .leading, spacing: 8) {
                        Text(notice.message)
                        Button {
                            lock.dismiss(notice)
                        } label: {
                            Text(ScreenText.okay).fontWeight(.semibold)
                        }
                    }
                }
                .foregroundStyle(Color("OnWarning"))
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color("Warning"), in: .rect(cornerRadius: 16))
            }
        }
    }

    /// The document that expires soonest, or already has. Others that need attention are counted.
    @ViewBuilder private var expiryBanner: some View {
        let attention = ExpiryText.needsAttention(library.documents.map(\.expiry), today: today)
        if let first = attention.first {
            let document = library.documents[first]
            HStack(spacing: 12) {
                Image(systemName: "clock")
                    .frame(width: 36, height: 36)
                    .background(Color("WarningIcon"), in: .circle)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(DocumentStyle.name(document.type)).font(.headline)
                    Text(ExpiryText.text(type: document.type, expiry: document.expiry, today: today))
                    if attention.count > 1 {
                        Text("banner.more \(attention.count - 1)").font(.subheadline)
                    }
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(Color("OnWarning"))
            .padding(14)
            .background(Color("Warning"), in: .rect(cornerRadius: 16))
            .accessibilityElement(children: .combine)
        }
    }
}

/// A document on the list: its type and expiry, in the type's colours.
struct DocumentTile: View {
    let document: Document
    let today: CalendarDate
    let wide: Bool

    var body: some View {
        let colours = DocumentStyle.tileColours(document.type)
        VStack(alignment: .leading, spacing: 6) {
            Text(DocumentStyle.name(document.type))
                .font(.footnote.weight(.bold))
                .tracking(0.6)
            Spacer(minLength: wide ? 0 : 12)
            if let label = DocumentStyle.shownLabel(document.label) {
                Text(verbatim: label).font(.headline).lineLimit(1)
            }
            Text(ExpiryText.text(type: document.type, expiry: document.expiry, today: today))
                .font(.footnote)
        }
        .foregroundStyle(Color(colours.foreground))
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: wide ? 0 : 104, alignment: .leading)
        .background(Color(colours.background), in: .rect(cornerRadius: 18))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("document.row")
    }
}

/// "Belum ada dokumen".
struct EmptyLibraryView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.shield")
                .font(.system(size: 26))
                .foregroundStyle(Color("OnAccent"))
                .frame(width: 52, height: 52)
                .background(Color.accentColor, in: .circle)
                .accessibilityHidden(true)
            Text("empty.title").font(.title3.bold())
            Text("empty.body").foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(.vertical, 60)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
    }
}

/// A white row on the grouped background, like a table cell.
struct GroupedRow: View {
    let title: LocalizedStringResource
    var value: String = ""
    var symbol: String?

    var body: some View {
        HStack(spacing: 12) {
            if let symbol { Image(systemName: symbol).foregroundStyle(.secondary).accessibilityHidden(true) }
            Text(title)
            Spacer()
            Text(verbatim: value).foregroundStyle(.secondary)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 50)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 12))
        .contentShape(.rect)
    }
}

extension Bundle {
    var shortVersion: String {
        object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }
}
