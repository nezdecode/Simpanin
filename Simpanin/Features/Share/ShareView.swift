//
//  ShareView.swift
//  Simpanin
//
//  Created by Inez Amanda on 4/11/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI
import VaultCore

/// Bagikan salinan: the purpose, page 1 as it will be shared, and Bagikan. The purpose isn't kept once the
/// sheet closes.
struct ShareView: View {
    @State private var model: ShareModel
    /// Set by Bagikan. The share runs in `.task(id:)`, so Batal and closing the sheet cancel it.
    @State private var request: UUID?
    @FocusState private var typing: Bool
    @Environment(\.dismiss) private var dismiss

    init(
        document: VaultCore.Document, pageReader: any PageReading, onShareSheetShown: @escaping () -> Void,
        onShareSheetEnded: @escaping () -> Void
    ) {
        _model = State(
            initialValue: ShareModel(
                document: document, pageReader: pageReader, copies: SharedCopies(),
                presenter: ActivitySharePresenter(), onShareSheetShown: onShareSheetShown,
                onShareSheetEnded: onShareSheetEnded))
    }

    var body: some View {
        NavigationStack {
            form
                .navigationTitle(Text("share.title"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbar }
        }
        .task { await model.loadPreview() }
        .task(id: model.mark) { await model.redrawPreview() }
        .task(id: request) {
            guard request != nil else { return }
            await model.share()
        }
        .onChange(of: model.phase) { _, phase in
            if phase == .closed { dismiss() }
        }
        .onDisappear { model.screenLeft() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            model.refreshDay()
        }
        .alert(Text("share.storageFullTitle"), isPresented: storageFull) {
            Button(role: .cancel) {
            } label: {
                Text(ScreenText.okay)
            }
        } message: {
            Text("share.storageFullMessage")
        }
    }

    private var storageFull: Binding<Bool> {
        Binding {
            model.problem == .storageFull
        } set: {
            if !$0 { model.problem = nil }
        }
    }

    private var isPreparing: Bool {
        if case .preparing = model.phase { true } else { false }
    }

    private var form: some View {
        Form {
            Section {
                preview
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            } footer: {
                Text(model.pageCount == 1 ? "share.markOnePage" : "share.markAllPages \(model.pageCount)")
            }
            Section {
                TextField(text: $model.purpose, prompt: Text("share.purposePlaceholder")) {
                    Text("share.purpose")
                }
                .focused($typing)
                .submitLabel(.done)
                .onSubmit { typing = false }
                .disabled(isPreparing)
                // A Form's text field shows no label of its own, and VoiceOver would read only the placeholder.
                .accessibilityLabel(Text("share.purpose"))
                .accessibilityIdentifier("share.purpose")
            } header: {
                Text("share.purpose")
            } footer: {
                Text("share.footer")
            }
            if isPreparing || shownProblem != nil {
                Section { status }
            }
        }
    }

    /// Progress while the copies are made, or why nothing was shared.
    @ViewBuilder private var status: some View {
        if case .preparing(let page, let count) = model.phase {
            HStack(spacing: 12) {
                ProgressView()
                Text("share.preparing \(page) \(count)")
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("share.progress")
        } else if let shownProblem {
            RefusalText(shownProblem).accessibilityIdentifier("share.problem")
        }
    }

    /// A full disk has its own alert. Page 1 that can't be opened is said at once, before Bagikan.
    private var shownProblem: LocalizedStringResource? {
        if case .failed = model.preview { return "share.pageUnavailable" }
        switch model.problem {
        case .pageUnavailable: return "share.pageUnavailable"
        case .notMade: return "share.notMade"
        case .storageFull, nil: return nil
        }
    }

    /// Never blank: a blank preview could look like a blank page.
    @ViewBuilder private var preview: some View {
        switch model.preview {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 200)
                .accessibilityIdentifier("share.previewLoading")
        case .failed:
            Image(systemName: "photo")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 200)
                .accessibilityHidden(true)
        case .shown(let page):
            Image(uiImage: UIImage(cgImage: model.markedPreview ?? page))
                .resizable()
                .scaledToFit()
                .clipShape(.rect(cornerRadius: 12))
                .accessibilityLabel(Text("share.previewLabel \(model.mark)"))
                .accessibilityIdentifier("share.preview")
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            // While the copies are made, Batal stops them and keeps the sheet; otherwise it closes it.
            Button {
                if isPreparing { request = nil } else { dismiss() }
            } label: {
                Text(ScreenText.cancel)
            }
            .accessibilityIdentifier("share.cancel")
        }
        ToolbarItem(placement: .confirmationAction) {
            Button {
                typing = false
                request = UUID()
            } label: {
                Text("button.share")
            }
            .disabled(!model.canShare)
            .accessibilityIdentifier("share.share")
        }
    }
}
