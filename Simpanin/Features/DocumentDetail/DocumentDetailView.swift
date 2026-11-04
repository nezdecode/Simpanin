//
//  DocumentDetailView.swift
//  Simpanin
//
//  Created by Inez Amanda on 28/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI
import VaultCore

/// One saved document: its pages, its fields with the number masked, Berlaku and Hapus. From Baru dihapus
/// it's read-only, with Pulihkan and Hapus permanen.
struct DocumentDetailView: View {
    let today: CalendarDate
    /// The user hid it from the expiry banner, so the screen offers "Tampilkan lagi".
    let hiddenFromBanner: Bool
    let onShowInBanner: () -> Void
    /// Whether the document is still in the list it was opened from. Read in `body`, so the screen hears when
    /// a restore from Baru dihapus's row lands after the row was tapped, and closes instead of showing a live
    /// document as deleted. The screen under it doesn't hear changes while this one covers it.
    let isListed: () -> Bool
    private let pageReader: any PageReading
    private let onShareSheetShown: () -> Void
    private let onShareSheetEnded: () -> Void
    @State private var model: DocumentDetailModel
    @State private var page = 0
    @State private var viewerShown = false
    /// The viewer's own page, handed back to `page` when it closes, so this screen stays still during a swipe.
    @State private var viewerPage = 0
    /// Coba lagi bumps it, so SwiftUI owns every load and cancels it when the screen goes.
    @State private var attempt = 0
    @State private var purgeAsked = false
    @State private var shareShown = false
    @Namespace private var transition
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    init(
        document: VaultCore.Document, store: any DocumentStoring & PageReading, today: CalendarDate,
        hiddenFromBanner: Bool, isListed: @escaping () -> Bool,
        onShowInBanner: @escaping () -> Void, onDelete: @escaping (DocumentID) async -> Bool,
        onRestore: @escaping (DocumentID) async -> Bool, onDeletePermanently: @escaping (DocumentID) async -> Bool,
        onShareSheetShown: @escaping () -> Void, onShareSheetEnded: @escaping () -> Void
    ) {
        self.today = today
        pageReader = store
        self.onShareSheetShown = onShareSheetShown
        self.onShareSheetEnded = onShareSheetEnded
        self.hiddenFromBanner = hiddenFromBanner
        self.onShowInBanner = onShowInBanner
        self.isListed = isListed
        _model = State(
            initialValue: DocumentDetailModel(
                document: document, store: store, pageReader: store, clipboard: SystemClipboard(),
                onDelete: onDelete, onRestore: onRestore, onDeletePermanently: onDeletePermanently))
    }

    private var document: VaultCore.Document { model.document }

    var body: some View {
        content
            .navigationTitle(Text(DocumentStyle.name(document.type)))
            .navigationBarTitleDisplayMode(.inline)
            .toast($model.toast)
            .task(id: attempt) { await model.load() }
            .onDisappear { model.screenLeft() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { model.appLeftForeground() }
            }
            .onChange(of: model.closed) { _, closed in
                if closed { dismiss() }
            }
            .onChange(of: model.phase) { _, phase in
                if phase == .gone { dismiss() }
            }
            // Initial too: the restore can land between the tap and this screen's first look.
            .onChange(of: isListed(), initial: true) { _, listed in
                if !listed { dismiss() }
            }
            .alert(Text("detail.deletePermanentlyTitle"), isPresented: $purgeAsked) {
                Button(role: .destructive) {
                    Task { await model.deletePermanently() }
                } label: {
                    Text("button.deletePermanently")
                }
                Button(role: .cancel) {
                } label: {
                    Text(ScreenText.cancel)
                }
            } message: {
                Text("detail.deletePermanentlyMessage")
            }
            .sheet(isPresented: $shareShown) {
                ShareView(
                    document: document, pageReader: pageReader, onShareSheetShown: onShareSheetShown,
                    onShareSheetEnded: onShareSheetEnded)
            }
            .fullScreenCover(isPresented: $viewerShown) {
                PageViewer(
                    count: document.pageIDs.count, current: $viewerPage, thumbnail: model.thumbnail,
                    image: model.fullPage, onSettle: { page = viewerPage }
                )
                .navigationTransition(.zoom(sourceID: page, in: transition))
            }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .loading, .gone:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed:
            LoadFailedView(title: "detail.loadFailed") { attempt += 1 }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded:
            loaded
        }
    }

    private var loaded: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    Text(dated).font(.subheadline).foregroundStyle(.secondary).padding(.horizontal, 20)
                    if let deletedAt = document.deletedAt {
                        Text(PurgeCountdown.notice(daysLeft: PurgeCountdown.daysLeft(deletedAt: deletedAt, now: .now)))
                            .font(.subheadline)
                            .noticeCard()
                            .padding(.horizontal, 20)
                            .accessibilityIdentifier("detail.purgeNotice")
                    }
                    if model.hasPages {
                        PagePager(pages: model.pages, selection: $page, transition: transition) { index in
                            page = index
                            viewerPage = index
                            model.viewerOpened()
                            viewerShown = true
                        }
                    }
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
            if !model.rows.isEmpty {
                Section {
                    ForEach(model.rows) { field in
                        DocumentFieldRow(
                            field: field, numberShown: model.numberShown, onToggleNumber: model.toggleNumber,
                            onCopy: { model.copy(field.key) })
                    }
                }
            }
            Section {
                validity
            } footer: {
                if hiddenFromBanner, !model.isDeleted { bannerLine }
            }
            if model.isDeleted {
                deletedActions
            } else {
                if model.canShare {
                    Section {
                        Button {
                            model.shareOpened()
                            shareShown = true
                        } label: {
                            Text("detail.share")
                        }
                        .accessibilityIdentifier("detail.share")
                    }
                }
                Section {
                    Button(role: .destructive) {
                        Task { await model.delete() }
                    } label: {
                        Text("button.delete")
                    }
                    .accessibilityIdentifier("detail.delete")
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder private var deletedActions: some View {
        Section {
            Button {
                Task { await model.restore() }
            } label: {
                Text("button.restore")
            }
            .buttonStyle(.prominent)
            .accessibilityIdentifier("detail.restore")
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }
        Section {
            Button(role: .destructive) {
                purgeAsked = true
            } label: {
                Text("button.deletePermanently")
            }
            .accessibilityIdentifier("detail.deletePermanently")
        }
    }

    /// "Saya · ditambahkan 12 Okt 2026", or without a label "Ditambahkan …"; from Baru dihapus, when it was
    /// deleted instead.
    private var dated: LocalizedStringResource {
        let label = DocumentStyle.shownLabel(document.label)
        if let deletedAt = document.deletedAt {
            let date = deletedAt.formatted(.indonesianDate(timeZone: .current))
            guard let label else { return "detail.deleted \(date)" }
            return "detail.labelDeleted \(label) \(date)"
        }
        let date = document.createdAt.formatted(.indonesianDate(timeZone: .current))
        guard let label else { return "detail.added \(date)" }
        return "detail.labelAdded \(label) \(date)"
    }

    private var validity: some View {
        let lines = ExpiryText.validity(type: document.type, expiry: document.expiry, today: today)
        return VStack(alignment: .leading, spacing: 2) {
            Text(lines.title).font(.subheadline).foregroundStyle(.secondary)
            switch lines.value {
            case .date(let date): Text(verbatim: date.displayText)
            case .phrase(let phrase): Text(phrase)
            }
            if let status = lines.status {
                Text(status.text).font(.subheadline).foregroundStyle(Color(status.color))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("detail.validity")
    }

    private var bannerLine: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("detail.bannerHidden")
            Button(action: onShowInBanner) {
                Text("detail.showInBanner")
            }
            .font(.footnote.weight(.semibold))
            .accessibilityIdentifier("detail.showInBanner")
        }
    }
}
