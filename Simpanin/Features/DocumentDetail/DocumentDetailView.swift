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

/// One saved document: its pages, its fields with the number masked, Berlaku and Hapus.
struct DocumentDetailView: View {
    let today: CalendarDate
    /// The user hid it from the expiry banner, so the screen offers "Tampilkan lagi".
    let hiddenFromBanner: Bool
    let onShowInBanner: () -> Void
    @State private var model: DocumentDetailModel
    @State private var page = 0
    @State private var viewerShown = false
    @Namespace private var transition
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    init(
        document: VaultCore.Document, store: any DocumentStoring & PageReading, today: CalendarDate,
        hiddenFromBanner: Bool,
        onShowInBanner: @escaping () -> Void, onDelete: @escaping (DocumentID) async -> Bool
    ) {
        self.today = today
        self.hiddenFromBanner = hiddenFromBanner
        self.onShowInBanner = onShowInBanner
        _model = State(
            initialValue: DocumentDetailModel(
                document: document, store: store, pageReader: store, clipboard: SystemClipboard(),
                onDelete: onDelete))
    }

    private var document: VaultCore.Document { model.document }

    var body: some View {
        content
            .navigationTitle(Text(DocumentStyle.name(document.type)))
            .navigationBarTitleDisplayMode(.inline)
            .toast($model.toast)
            .task { await model.load() }
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
            .fullScreenCover(isPresented: $viewerShown) {
                PageViewer(count: document.pageIDs.count, selection: $page, image: model.fullPage)
                    .navigationTransition(.zoom(sourceID: page, in: transition))
            }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .loading, .gone:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed:
            LoadFailedView(title: "detail.loadFailed") { Task { await model.load() } }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded:
            loaded
        }
    }

    private var loaded: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    Text(added).font(.subheadline).foregroundStyle(.secondary).padding(.horizontal, 20)
                    if model.hasPages {
                        PagePager(pages: model.pages, selection: $page, transition: transition) { index in
                            page = index
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
                if hiddenFromBanner { bannerLine }
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
        .listStyle(.insetGrouped)
    }

    /// "Saya · ditambahkan 12 Okt 2026", or without a label only "ditambahkan …".
    private var added: LocalizedStringResource {
        let date = document.createdAt.formatted(.indonesianDate(timeZone: .current))
        guard let label = DocumentStyle.shownLabel(document.label) else { return "detail.added \(date)" }
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
