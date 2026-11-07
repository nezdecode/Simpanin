//
//  ReviewView.swift
//  Simpanin
//
//  Created by Inez Amanda on 16/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Parsers
import SwiftUI
import VaultCore

/// "Periksa data": the pages and what the scan read, to check and correct before "Simpan ke vault".
struct ReviewView: View {
    @Bindable var review: ReviewModel
    let source: ScanSource
    /// Vision is still reading the pages.
    let reading: Bool
    let onCancel: () -> Void
    let onRescan: () -> Void
    let onSave: () -> Void
    @State private var typePickerShown = false
    @State private var expiryPickerShown = false
    @State private var nikMissingShown = false
    @State private var otherPagesShown = false
    @State private var duplicateShown = false
    /// What the duplicate alert names, kept while it closes: answering it clears the model's duplicate.
    @State private var duplicateName = DocumentType.ktp
    @State private var discardConfirmShown = false
    @State private var viewerShown = false
    @State private var viewerPage = 0
    @Namespace private var transition
    /// Counts refused taps on Simpan, for the error haptic.
    @State private var refusals = 0
    @FocusState private var focusedField: String?
    @AccessibilityFocusState private var voiceOverField: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label {
                        Text("review.onDevice")
                    } icon: {
                        Image(systemName: "iphone")
                    }
                    .foregroundStyle(.secondary)
                }
                ReviewPagesSection(
                    thumbnails: review.thumbnails, notes: review.pageNotes,
                    footnote: ReviewText.pagesFootnote(source), reading: reading, transition: transition
                ) { index in
                    // The keyboard closes, so it isn't back over the form when the viewer closes.
                    focusedField = nil
                    viewerPage = index
                    viewerShown = true
                }
                if reading {
                    Section {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("review.reading")
                        }
                    }
                } else {
                    Section { typeRow }
                    DocumentFormSections(
                        label: $review.label, form: review.form, showsBirthDateMatch: review.showsBirthDateMatch,
                        focus: $focusedField, voiceOverFocus: $voiceOverField,
                        onChange: { review.setValue($0, for: $1) })
                    ValiditySection(
                        type: review.type, hasExpiry: review.hasExpiry, expiry: review.expiry,
                        note: review.expiryNote.map { FormText.text(for: $0, numberKey: review.numberKey) },
                        onChange: { review.setExpiry($0) }, onPick: { expiryPickerShown = true })
                }
            }
            // Nothing in the form changes while a save is being written.
            .disabled(review.saving)
            // The number pad has no Return: Selesai in the bar, or a swipe down the form, closes it.
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(Text("review.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // Nothing can be cancelled while a save is being written.
                    Button {
                        discardConfirmShown = true
                    } label: {
                        Text(ScreenText.cancel)
                    }
                    .disabled(review.saveInProgress)
                    .accessibilityIdentifier("review.cancel")
                }
                // In the bar, not above the keyboard: a condition inside the keyboard's own toolbar never
                // showed on an iPhone with iOS 27. The number pad has no Return, so this is its way out.
                if focusedField != nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            focusedField = nil
                        } label: {
                            Text(ScreenText.done)
                        }
                        .accessibilityIdentifier("review.done")
                    }
                } else {
                    // In the bar, so it's in reach wherever the form is scrolled to.
                    ToolbarItem(placement: .primaryAction) {
                        Button(action: onRescan) { Text(ReviewText.rescan(source)) }
                            .disabled(reading || review.saveInProgress)
                            .accessibilityIdentifier("review.rescan")
                    }
                }
            }
            // Batal throws the scan away, so it always asks first.
            .alert(Text(ReviewText.discardConfirm(source)), isPresented: $discardConfirmShown) {
                Button(role: .destructive, action: onCancel) { Text("review.discard") }
                Button(role: .cancel) {
                } label: {
                    Text("review.keepChecking")
                }
            } message: {
                if let message = ReviewText.discardMessage(source) { Text(message) }
            }
            // VoiceOver's escape closes the keyboard while editing, and otherwise works like Batal.
            .accessibilityAction(.escape) {
                if focusedField != nil {
                    focusedField = nil
                } else if !review.saveInProgress {
                    discardConfirmShown = true
                }
            }
            // Hidden while typing: saving only makes sense once a field is done, and the bar would ride up
            // over the keyboard.
            .safeAreaInset(edge: .bottom) {
                if focusedField == nil {
                    SaveBar(title: "review.save", saving: review.saving, isDisabled: reading, onSave: trySave)
                }
            }
            .sheet(isPresented: $typePickerShown) {
                TypePickerView(selection: $review.type)
            }
            .scanPageViewer(isPresented: $viewerShown, page: $viewerPage, review: review, transition: transition)
            .sensoryFeedback(.error, trigger: refusals)
            // A field is judged once it's left, as typing is done.
            .onChange(of: focusedField) { left, _ in
                if let left { review.fieldLeft(left) }
            }
            // Cancel roles, so VoiceOver's escape gesture answers like the default button.
            .alert(Text("review.nikMissing"), isPresented: $nikMissingShown) {
                Button(role: .cancel) {
                    // Simpan stays visible until the NIK has focus, so asking ends only then.
                    UIApplication.shared.afterAlertCloses {
                        review.alertAnswered()
                        focusedField = FieldKey.nik
                    }
                } label: {
                    Text("review.fillNIK")
                }
                .keyboardShortcut(.defaultAction)
                Button(action: saveWithoutNIK) { Text("review.saveAnyway") }
            }
            // A page read as another document is saved with this one, so Simpan says so; Kembali is the default.
            .alert(Text("review.otherPages"), isPresented: $otherPagesShown) {
                Button(role: .cancel) {
                } label: {
                    Text("review.goBack")
                }
                .keyboardShortcut(.defaultAction)
                Button(action: onSave) { Text("review.otherPages.save") }
            } message: {
                Text(verbatim: review.pageNotes.saveWarning ?? "")
            }
            // However the pages alert closes, it was the last question before the save.
            .onChange(of: otherPagesShown) { _, shown in
                if !shown { review.alertAnswered() }
            }
            // The check finishes inside the save, often while the pages or NIK alert is still closing, and
            // an alert shown then can be dropped; one still up after the wait means the next Simpan asks.
            // Initial too: a view rebuilt while a duplicate waits still opens its alert.
            .onChange(of: review.duplicate, initial: true) { _, found in
                guard found != nil else { return }
                UIApplication.shared.afterAlertCloses {
                    // Read again: the wait may have outlasted the duplicate.
                    guard let found = review.duplicate else { return }
                    if UIApplication.shared.showsAlert {
                        review.duplicateAnswered()
                    } else {
                        duplicateName = found.name
                        duplicateShown = true
                    }
                }
            }
            // Kembali is the default: the likeliest reason is a document saved before and forgotten.
            .alert(Text(FormText.duplicateTitle(duplicateName)), isPresented: $duplicateShown) {
                Button(role: .cancel) {
                } label: {
                    Text("review.goBack")
                }
                .keyboardShortcut(.defaultAction)
                Button {
                    review.acceptDuplicate()
                    onSave()
                } label: {
                    Text("review.duplicate.save")
                }
            } message: {
                Text("review.duplicate.message")
            }
            .onChange(of: duplicateShown) { _, shown in
                if !shown { review.duplicateAnswered() }
            }
            .sheet(isPresented: $expiryPickerShown) {
                ExpiryCalendar(title: DocumentFieldStyle.validityTitle(for: review.type)) { review.setExpiry($0) }
            }
        }
    }

    private var typeRow: some View {
        Button {
            typePickerShown = true
        } label: {
            LabeledContent {
                HStack(spacing: 6) {
                    Text(DocumentStyle.name(review.type))
                    DisclosureChevron()
                }
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("review.type").foregroundStyle(Color.primary)
                    if let note = review.typeNote {
                        WarningText(FormText.text(for: note, numberKey: review.numberKey, onType: true))
                    }
                }
            }
        }
        .accessibilityIdentifier("review.type")
    }
}

extension ReviewView {
    /// Simpan never quietly does nothing: a wrong value takes the user to its field, with a haptic, and
    /// VoiceOver reads the reason; otherwise it asks what `ReviewModel.saveStep` says, or saves.
    private func trySave() {
        guard !review.saving, let step = review.saveStep() else { return }
        switch step {
        case .refuse(let key):
            focusedField = key
            refusals += 1
            // VoiceOver goes to the field and reads its label, which carries the reason.
            voiceOverField = key
        case .askNIK: nikMissingShown = true
        case .askPages: otherPagesShown = true
        case .save: onSave()
        }
    }

    private func saveWithoutNIK() {
        if review.saveStepWithoutNIK() == .askPages {
            UIApplication.shared.afterAlertCloses {
                // Past the wait's limit the NIK alert can still be up, and this one would never show or
                // close; the next Simpan asks again instead.
                if UIApplication.shared.showsAlert { review.alertAnswered() } else { otherPagesShown = true }
            }
        } else {
            onSave()
        }
    }
}
