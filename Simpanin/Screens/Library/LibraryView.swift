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
    @State private var scanShown = false
    @State private var passcodeNeededShown = false
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.scenePhase) private var scenePhase

    init(vault: AppVault, lock: LockController) {
        self.vault = vault
        self.lock = lock
        let hidden = HiddenBannerFile(
            url: HiddenBannerFile.url(in: vault.locations), protector: DataProtectionFileProtector())
        _library = State(initialValue: LibraryModel(store: Self.documentStore(for: vault), hidden: hidden))
    }

    private var today: CalendarDate { library.today }

    private func scanRead() {
        #if DEBUG
            // Lets a UI test check the privacy cover sits above the scan flow: a recording starts once the
            // review shows and stops again, so the test sees the review before, under and after the cover.
            if UITestSetup.capturesAfterScan {
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    lock.screenCaptured = true
                    try? await Task.sleep(for: .seconds(4))
                    lock.screenCaptured = false
                }
            }
        #endif
    }

    private static var canScan: Bool {
        #if DEBUG
            if UITestSetup.scansSynthetically { return true }
        #endif
        return DocumentCamera.isSupported
    }

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
                    } else if library.documents.isEmpty {
                        EmptyLibraryView()
                    } else {
                        ExpiryBanner(documents: library.bannerDocuments, today: today, onHide: library.hideFromBanner)
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
                    if !library.loadFailed {
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
            // A night may have passed while the app was away.
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { library.refreshDay() }
            }
            .fullScreenCover(isPresented: $scanShown) {
                ScanFlowView(
                    store: Self.documentStore(for: vault), onScanStarted: lock.scanStarted,
                    onScanEnded: lock.scanEnded, onRead: scanRead
                ) {
                    scanShown = false
                    Task { await library.reload() }
                }
            }
            .alert(Text("recovery.passcodeNeeded"), isPresented: $passcodeNeededShown) {
                if let url = URL.appSettings {
                    Link(destination: url) { Text(ScreenText.openSettings) }
                }
                Button(role: .cancel) {
                } label: {
                    Text(ScreenText.cancel)
                }
            }
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
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                // The vault's key needs a passcode; checked before the first scan, as the design doc says.
                if lock.passcodeState.stopsScanning {
                    passcodeNeededShown = true
                } else {
                    scanShown = true
                }
            } label: {
                Label {
                    Text("main.scan")
                } icon: {
                    Image(systemName: "plus")
                }
            }
            // A phone without VisionKit's document camera can't scan; nothing pretends it can.
            .disabled(library.loadFailed || !Self.canScan)
            .accessibilityIdentifier("list.scan")
        }
        #if DEBUG
            // A synthetic sample document, for the UI tests only: on a phone, next to "+", it was easy to
            // mistake for scanning, and real scans now fill the list.
            if UITestSetup.isActive {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await library.addSample() }
                    } label: {
                        Label {
                            Text("debug.addSample")
                        } icon: {
                            Image(systemName: "doc.badge.plus")
                        }
                    }
                    // Saving while the list can't load would only confuse; it can't harm the vault.
                    .disabled(library.loadFailed)
                    .accessibilityIdentifier("list.addSample")
                }
            }
        #endif
    }
}
