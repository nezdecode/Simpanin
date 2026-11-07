//
//  EditDocumentView.swift
//  Simpanin
//
//  Created by Inez Amanda on 7/11/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import CoreGraphics
import SwiftUI
import VaultCore

/// Edit dokumen: the label, fields and expiry of a saved document, with its pages above them to check a
/// value against. The type and the pages can't be changed here.
struct EditDocumentView: View {
    @State private var model: EditDocumentModel
    /// The document screen's reduced pages; the sheet decrypts nothing of its own.
    private let pages: [DocumentDetailModel.PageState]
    private let thumbnail: (Int) -> CGImage?
    private let fullPage: (Int) async -> CGImage?
    private let onSaved: () -> Void
    private let onUnsavedChange: (Bool) -> Void
    @State private var page = 0
    @State private var viewerShown = false
    @State private var viewerPage = 0
    @State private var expiryPickerShown = false
    @State private var nikMissingShown = false
    @State private var duplicateShown = false
    /// What the duplicate alert names, kept while it closes: answering it clears the model's duplicate.
    @State private var duplicateName = DocumentType.ktp
    @State private var discardConfirmShown = false
    /// Simpan bumps it; the save runs in `.task(id:)`, so a lock that takes the sheet away cancels it.
    @State private var saves = 0
    /// Counts refused taps on Simpan, for the error haptic.
    @State private var refusals = 0
    @FocusState private var focusedField: String?
    @AccessibilityFocusState private var voiceOverField: String?
    @Namespace private var transition
    @Environment(\.dismiss) private var dismiss

    /// - Parameters:
    ///   - onSaved: runs the moment the vault has the edit, before the sheet closes.
    ///   - onUnsavedChange: whether the sheet holds changes a lock would drop.
    init(
        document: VaultCore.Document, fields: DocumentFields, store: any DocumentStoring,
        pages: [DocumentDetailModel.PageState], thumbnail: @escaping (Int) -> CGImage?,
        fullPage: @escaping (Int) async -> CGImage?, onSaved: @escaping () -> Void,
        onUnsavedChange: @escaping (Bool) -> Void
    ) {
        _model = State(initialValue: EditDocumentModel(document: document, fields: fields, store: store))
        self.pages = pages
        self.thumbnail = thumbnail
        self.fullPage = fullPage
        self.onSaved = onSaved
        self.onUnsavedChange = onUnsavedChange
    }

    var body: some View {
        NavigationStack {
            form
                .navigationTitle(Text("edit.title"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbar }
                // VoiceOver's escape closes the keyboard while editing, and otherwise works like Batal.
                .accessibilityAction(.escape) {
                    if focusedField != nil { focusedField = nil } else { cancel() }
                }
                // Hidden while typing, as in Periksa data: the bar would ride up over the keyboard.
                .safeAreaInset(edge: .bottom) {
                    if focusedField == nil {
                        SaveBar(
                            title: "edit.save", saving: model.saving, isDisabled: !model.hasChanges, onSave: trySave)
                    }
                }
                .task(id: saves) {
                    guard saves > 0 else { return }
                    let saved = await model.save {
                        // Before anything else runs, so a lock right after never calls the edit dropped.
                        onUnsavedChange(false)
                        onSaved()
                    }
                    if saved { dismiss() }
                }
                .onChange(of: model.hasChanges, initial: true) { _, changed in onUnsavedChange(changed) }
                .sensoryFeedback(.error, trigger: refusals)
                // A field is judged once it's left, as typing is done.
                .onChange(of: focusedField) { left, _ in
                    if let left { model.fieldLeft(left) }
                }
                .discardAlert(isPresented: $discardConfirmShown) {
                    onUnsavedChange(false)
                    dismiss()
                }
                .nikMissingAlert(isPresented: $nikMissingShown, onFill: fillNIK, onSave: saveWithoutNIK)
                .duplicateAlert(model: model, isPresented: $duplicateShown, name: $duplicateName) { saves += 1 }
                .saveErrorAlert(error: $model.saveError)
                .sheet(isPresented: $expiryPickerShown) {
                    ExpiryCalendar(title: DocumentFieldStyle.validityTitle(for: model.document.type)) {
                        model.setExpiry($0)
                    }
                }
                .fullScreenCover(isPresented: $viewerShown) {
                    PageViewer(
                        count: pages.count, current: $viewerPage, thumbnail: thumbnail, image: fullPage,
                        onSettle: { page = viewerPage }
                    )
                    .navigationTransition(.zoom(sourceID: page, in: transition))
                }
        }
        // A swipe down would lose the changes without asking; Batal asks.
        .interactiveDismissDisabled(model.hasChanges || model.saving)
    }

    private var form: some View {
        Form {
            if !pages.isEmpty {
                Section {
                    PagePager(pages: pages, selection: $page, transition: transition) { index in
                        // The keyboard closes, so it isn't back over the form when the viewer closes.
                        focusedField = nil
                        page = index
                        viewerPage = index
                        viewerShown = true
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            }
            Section {
                LabeledContent {
                    Text(DocumentStyle.name(model.document.type))
                } label: {
                    Text("review.type")
                }
                .accessibilityIdentifier("edit.type")
            }
            DocumentFormSections(
                label: $model.label, form: model.form, showsBirthDateMatch: false, focus: $focusedField,
                voiceOverFocus: $voiceOverField, onChange: { model.setValue($0, for: $1) })
            ValiditySection(
                type: model.document.type, hasExpiry: model.hasExpiry, expiry: model.expiry, note: nil,
                onChange: { model.setExpiry($0) }, onPick: { expiryPickerShown = true })
        }
        // Nothing in the form changes while a save is being written.
        .disabled(model.saving)
        .keepsFieldCopiesLocal(model.form.shownValues, whileEditing: focusedField != nil)
        // The number pad has no Return: Selesai in the bar, or a swipe down the form, closes it.
        .scrollDismissesKeyboard(.interactively)
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(action: cancel) { Text(ScreenText.cancel) }
                .disabled(model.saving)
                .accessibilityIdentifier("edit.cancel")
        }
        // The number pad has no Return, so Selesai in the bar is its way out.
        if focusedField != nil {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    focusedField = nil
                } label: {
                    Text(ScreenText.done)
                }
                .accessibilityIdentifier("edit.done")
            }
        }
    }
}

extension EditDocumentView {
    /// Batal closes at once when nothing changed, and asks first when something did.
    private func cancel() {
        guard !model.saving else { return }
        if model.hasChanges { discardConfirmShown = true } else { dismiss() }
    }

    /// As in Periksa data: a wrong value takes the user to its field, with a haptic, and VoiceOver reads the
    /// reason; an emptied NIK is asked about; otherwise the edit is saved.
    private func trySave() {
        guard !model.saving, model.hasChanges, let step = model.saveStep() else { return }
        switch step {
        case .refuse(let key):
            focusedField = key
            refusals += 1
            voiceOverField = key
        case .askNIK: nikMissingShown = true
        case .save: saves += 1
        }
    }

    private func fillNIK() {
        // Simpan stays visible until the NIK has focus, so asking ends only then.
        UIApplication.shared.afterAlertCloses {
            model.alertAnswered()
            focusedField = FieldKey.nik
        }
    }

    private func saveWithoutNIK() {
        if model.saveStepWithoutNIK() == .save { saves += 1 }
    }
}

extension View {
    /// "Buang perubahan?" after Batal; Lanjut edit is the default.
    fileprivate func discardAlert(isPresented: Binding<Bool>, onDiscard: @escaping () -> Void) -> some View {
        alert(Text("edit.discardTitle"), isPresented: isPresented) {
            Button(role: .destructive, action: onDiscard) { Text("review.discard") }
            Button(role: .cancel) {
            } label: {
                Text("edit.keepEditing")
            }
        } message: {
            Text("edit.discardMessage")
        }
    }

    /// The same question as in Periksa data, only for a NIK this edit emptied. Cancel role, so VoiceOver's
    /// escape answers like the default button.
    fileprivate func nikMissingAlert(
        isPresented: Binding<Bool>, onFill: @escaping () -> Void, onSave: @escaping () -> Void
    ) -> some View {
        alert(Text("review.nikMissing"), isPresented: isPresented) {
            Button(role: .cancel, action: onFill) { Text("review.fillNIK") }
                .keyboardShortcut(.defaultAction)
            Button(action: onSave) { Text("review.saveAnyway") }
        }
    }

    /// A changed number another document already has. The check finishes inside the save, so its alert waits
    /// for any other to close, as in Periksa data; Kembali is the default.
    fileprivate func duplicateAlert(
        model: EditDocumentModel, isPresented: Binding<Bool>, name: Binding<DocumentType>,
        onSave: @escaping () -> Void
    ) -> some View {
        onChange(of: model.duplicate, initial: true) { _, found in
            guard found != nil else { return }
            UIApplication.shared.afterAlertCloses {
                guard let found = model.duplicate else { return }
                if UIApplication.shared.showsAlert {
                    model.duplicateAnswered()
                } else {
                    name.wrappedValue = found.name
                    isPresented.wrappedValue = true
                }
            }
        }
        .alert(Text(FormText.duplicateTitle(name.wrappedValue)), isPresented: isPresented) {
            Button(role: .cancel) {
            } label: {
                Text("review.goBack")
            }
            .keyboardShortcut(.defaultAction)
            Button {
                model.acceptDuplicate()
                onSave()
            } label: {
                Text("review.duplicate.save")
            }
        } message: {
            Text("review.duplicate.message")
        }
        .onChange(of: isPresented.wrappedValue) { _, shown in
            if !shown { model.duplicateAnswered() }
        }
    }

    /// The save alert, as on the list: the sheet stays open with the edits.
    fileprivate func saveErrorAlert(error: Binding<RecoveryScreen?>) -> some View {
        alert(
            error.wrappedValue.map { Text(RecoveryContent($0).message) } ?? Text(verbatim: ""),
            isPresented: Binding(isPresent: error)
        ) {
            Button {
                error.wrappedValue = nil
            } label: {
                Text(ScreenText.okay)
            }
        } message: {
            if error.wrappedValue == .storageFullOnSave { Text("saveFull.hint") }
        }
    }
}
