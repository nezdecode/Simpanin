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
    /// The scan flow's source, set when it opens. One value, so the cover never builds the flow with the
    /// source before: that opened the camera, and its permission prompt, for "Pilih dari Foto".
    @State private var adding: ScanSource?
    @State private var passcodeNeededShown = false
    @State private var path = NavigationPath()
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.scenePhase) private var scenePhase
    private let dayChanges = NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)

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
            // The pages can be read before the flow is on screen, while the "+" menu is still closing.
            if UITestSetup.capturesAfterScan {
                Task {
                    try? await Task.sleep(for: .seconds(4))
                    lock.screenCaptured = true
                    try? await Task.sleep(for: .seconds(4))
                    lock.screenCaptured = false
                }
            }
        #endif
    }

    private static func documentStore(for vault: AppVault) -> any DocumentStoring & PageReading {
        #if DEBUG
            if UITestSetup.isActive { return UITestSetup.documentStore(for: vault) }
        #endif
        return vault.store
    }

    var body: some View {
        NavigationStack(path: $path) {
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
                        EmptyLibraryView(hasCamera: DocumentCamera.isAvailable, onAdd: add(from:))
                    } else {
                        ExpiryBanner(
                            documents: library.bannerDocuments, today: today, onOpen: { path.append($0.id) },
                            onHide: library.hideFromBanner)
                        Text("main.allDocuments").font(.title3.weight(.semibold)).padding(.top, 8)
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(library.documents) { document in
                                NavigationLink(value: document.id) {
                                    DocumentTile(document: document, today: today, wide: typeSize.isAccessibilitySize)
                                }
                                .buttonStyle(.plain)
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
                            RecentlyDeletedView(library: library, documentScreen: documentScreen)
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
            .toast($library.notice)
            .navigationTitle(Text("list.title"))
            .navigationDestination(for: DocumentID.self) { id in
                // Still found in Baru dihapus right after Hapus, while the screen closes.
                if let document = (library.documents + library.deleted).first(where: { $0.id == id }) {
                    documentScreen(document)
                }
            }
            .toolbar { toolbar }
            .task { await library.reload() }
            // The scan chosen on the welcome screen starts at once and without the slide-up, so the empty
            // list barely shows. The passcode was checked when the vault was created.
            .onAppear {
                guard let scan = lock.takePendingScan() else { return }
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { adding = scan }
            }
            // A night may have passed while the app was away.
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { library.refreshDay() }
            }
            // Midnight with the app open, and a changed time zone.
            .onReceive(dayChanges) { _ in library.refreshDay() }
            .fullScreenCover(item: $adding) { source in
                ScanFlowView(
                    source: source, store: Self.documentStore(for: vault), onScanStarted: lock.scanStarted,
                    onScanEnded: lock.scanEnded, onRead: scanRead,
                    onDone: {
                        adding = nil
                        Task { await library.reload() }
                    })
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
        }
        // On the stack, not its root, so a failed Hapus on the document screen shows it too.
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

    private func documentScreen(_ document: VaultCore.Document) -> DocumentDetailView {
        DocumentDetailView(
            document: document, store: Self.documentStore(for: vault), today: today,
            hiddenFromBanner: library.offersShowInBanner(document.id),
            isListed: {
                (document.deletedAt == nil ? library.documents : library.deleted).contains { $0.id == document.id }
            },
            onShowInBanner: { library.showInBanner(document.id) }, onDelete: library.delete,
            onRestore: library.restore, onDeletePermanently: library.deletePermanently,
            onShareSheetShown: lock.shareSheetShown, onShareSheetEnded: lock.shareSheetEnded)
    }

    /// Two columns, or one at the accessibility text sizes, where two would not fit.
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12), count: typeSize.isAccessibilitySize ? 1 : 2)
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                Task {
                    await lock.lock()
                    #if DEBUG
                        // A recording that starts once the vault is locked, for the cover's UI test.
                        if UITestSetup.recordsAfterLock { lock.screenCaptured = true }
                    #endif
                }
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
                SettingsView(vault: vault, lock: lock, library: library, documentScreen: documentScreen)
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
            AddDocumentMenu(hasCamera: DocumentCamera.isAvailable, isDisabled: library.loadFailed, onAdd: add(from:))
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

    /// The vault's key needs a passcode, so each scan or import checks for one first.
    private func add(from source: ScanSource) {
        if lock.passcodeState.stopsScanning {
            passcodeNeededShown = true
        } else {
            adding = source
        }
    }
}
