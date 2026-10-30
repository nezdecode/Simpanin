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
                    thumbnails: review.thumbnails, notes: review.pageNotes, reading: reading, transition: transition
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
                    labelSection
                    if !review.fieldKeys.isEmpty {
                        Section {
                            ForEach(review.fieldKeys, id: \.self) { key in fieldRow(key) }
                        }
                    }
                    ValiditySection(
                        type: review.type, hasExpiry: review.hasExpiry, expiry: review.expiry,
                        note: review.expiryNote.map { Self.text(for: $0, numberKey: review.numberKey) },
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
                        Button(action: onRescan) { Text("review.rescan") }
                            .disabled(reading || review.saveInProgress)
                            .accessibilityIdentifier("review.rescan")
                    }
                }
            }
            // Batal throws the scan away, so it always asks first.
            .alert(Text("review.discardConfirm"), isPresented: $discardConfirmShown) {
                Button(role: .destructive, action: onCancel) { Text("review.discard") }
                Button(role: .cancel) {
                } label: {
                    Text("review.keepChecking")
                }
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
                    Button(action: trySave) { Text("review.save") }
                        .buttonStyle(.prominent)
                        .disabled(reading || review.saving)
                        .padding(16)
                        .accessibilityIdentifier("review.save")
                }
            }
            .sheet(isPresented: $typePickerShown) {
                TypePickerView(selection: $review.type)
            }
            // On the screen, not the pages section: in a Form, a Section's modifiers go to its rows.
            .fullScreenCover(isPresented: $viewerShown) {
                // Nothing under the viewer follows its page, so there's nothing to hand back.
                PageViewer(
                    count: review.pages.count, current: $viewerPage, thumbnail: review.thumbnail,
                    image: review.viewerPage, onSettle: {}
                )
                .checkedFieldsBar(review.checkedFields)
                // Also what lets a swipe down close it.
                .navigationTransition(.zoom(sourceID: viewerPage, in: transition))
            }
            .sensoryFeedback(.error, trigger: refusals)
            // A field is judged once it's left, as typing is done.
            .onChange(of: focusedField) { left, _ in
                if let left { review.fieldLeft(left) }
            }
            // Cancel roles, so VoiceOver's escape gesture answers like the default button.
            .alert(Text("review.nikMissing"), isPresented: $nikMissingShown) {
                Button(role: .cancel) {
                    // Simpan stays visible until the NIK has focus, so asking ends only then.
                    afterAlertCloses {
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
                afterAlertCloses {
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
            .alert(Text(Self.duplicateTitle(duplicateName)), isPresented: $duplicateShown) {
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
                        WarningText(Self.text(for: note, numberKey: review.numberKey, onType: true))
                    }
                }
            }
        }
        .accessibilityIdentifier("review.type")
    }

    private var labelSection: some View {
        Section {
            TextField(text: $review.label, prompt: Text("review.labelPlaceholder")) {
                Text("review.label")
            }
            .focused($focusedField, equals: Self.labelFocus)
            .autocorrectionDisabled()
            .submitLabel(.next)
            .onSubmit { focusField(after: Self.labelFocus) }
            .accessibilityIdentifier("review.label")
        } header: {
            Text("review.label")
        } footer: {
            if review.labelLooksLikeANumber {
                Label {
                    Text("review.labelIsNumber")
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                }
                .foregroundStyle(Color(.onWarning))
                .accessibilityIdentifier("review.labelIsNumber")
            } else {
                Text("review.labelHint")
            }
        }
    }

    private func fieldRow(_ key: String) -> some View {
        let note = review.note(for: key)
        var refusal: LocalizedStringResource?
        var markReason: LocalizedStringResource?
        if case .refusal(let problem) = note { refusal = Self.reason(for: problem) }
        if case .mark(let reason?) = note { markReason = Self.reasonText(reason, numberKey: review.numberKey) }
        let match = review.showsBirthDateMatch && key == review.numberKey
        return FieldRow(
            key: key, value: review.values[key] ?? "", isLast: key == review.fieldKeys.last, refusal: refusal,
            markReason: markReason, footnote: match ? "review.birthDateMatch" : nil, focus: $focusedField,
            voiceOverFocus: $voiceOverField, onChange: { review.setValue($0, for: key) },
            onSubmit: { focusField(after: key) })
    }
}

extension ReviewView {
    private static let labelFocus = "label"

    /// Simpan never quietly does nothing: a wrong value takes the user to its field, with a haptic, and
    /// VoiceOver reads the reason; otherwise it asks what `ReviewModel.saveStep` says, or saves.
    private func trySave() {
        guard let step = review.saveStep() else { return }
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
            afterAlertCloses {
                // Past the wait's limit the NIK alert can still be up, and this one would never show or
                // close; the next Simpan asks again instead.
                if UIApplication.shared.showsAlert { review.alertAnswered() } else { otherPagesShown = true }
            }
        } else {
            onSave()
        }
    }

    /// Focus set, or an alert shown, while an alert is still closing can be dropped, so it waits until the
    /// alert is off the screen, checked rather than guessed with a delay. After two seconds at most it runs
    /// anyway.
    private func afterAlertCloses(_ action: @escaping () -> Void) {
        Task {
            for _ in 0..<40 where UIApplication.shared.showsAlert {
                try? await Task.sleep(for: .milliseconds(50))
            }
            action()
        }
    }

    /// Return moves to the next field, in the order the screen shows them; after the last, the keyboard
    /// closes.
    private func focusField(after current: String) {
        let order = [Self.labelFocus] + review.fieldKeys
        guard let index = order.firstIndex(of: current), index + 1 < order.count else {
            focusedField = nil
            return
        }
        focusedField = order[index + 1]
    }

    /// What shows under the type or the expiry: "Periksa lagi", with its reason when one is known.
    static func text(for note: ReviewModel.Note, numberKey: String?, onType: Bool = false) -> LocalizedStringResource {
        switch note {
        case .refusal(let problem): reason(for: problem)
        case .mark(nil): "review.checkAgain"
        case .mark(let reason?):
            "review.markWithReason \(String(localized: reasonText(reason, numberKey: numberKey, onType: onType)))"
        case .dateFromAnotherType: "review.markWithReason \(String(localized: "review.dateFromAnotherType"))"
        }
    }

    /// The text of a reason. Three name the number that holds the birth date: the NIK on a KTP, the number
    /// on a SIM. On the type, a lookalike is a SIM class read with a 1 for an I. The key is built as a plain
    /// string: interpolated, the code would become an argument.
    static func reasonText(_ reason: CheckReason, numberKey: String?, onType: Bool = false) -> LocalizedStringResource {
        var key = "review.reason." + reason.rawValue
        if onType && reason == .lookalike { key += ".type" }
        if [.noDateInNumber, .disagreesWithBirthDate, .sexDisagrees].contains(reason) {
            key += numberKey == FieldKey.simNumber ? ".simNumber" : ".nik"
        }
        return LocalizedStringResource(String.LocalizationValue(key))
    }

    /// "Kamu sudah punya SIM A dengan nomor ini.": a KTP has a NIK, a SIM a number.
    static func duplicateTitle(_ name: DocumentType) -> LocalizedStringResource {
        name == .ktp ? "review.duplicate.ktp" : "review.duplicate.sim \(String(localized: DocumentStyle.name(name)))"
    }

    static func reason(for problem: ReviewModel.FieldProblem) -> LocalizedStringResource {
        switch problem {
        case .notADate: "review.notADate"
        case .birthDateInFuture: "review.birthDateInFuture"
        case .nikLength: "review.nikLength"
        }
    }

    static func keyboard(for key: String) -> UIKeyboardType {
        switch key {
        case FieldKey.nik: .numberPad
        case FieldKey.birthDate: .numberPad
        case FieldKey.simNumber: .numbersAndPunctuation
        default: .default
        }
    }
}
