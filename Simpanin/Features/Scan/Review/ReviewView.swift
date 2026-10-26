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
    @State private var discardConfirmShown = false
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
                Section {
                    PageStrip(pages: review.pages, notes: review.pageNotes)
                } footer: {
                    pagesFooter
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
                    validitySection
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
                    .disabled(review.saving)
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
                            .disabled(reading || review.saving)
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
                } else if !review.saving {
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
            .sensoryFeedback(.error, trigger: refusals)
            // A field is judged once it's left, as typing is done.
            .onChange(of: focusedField) { left, _ in
                if let left { review.fieldLeft(left) }
            }
            .alert(Text("review.nikMissing"), isPresented: $nikMissingShown) {
                Button {
                    afterAlertCloses { focusedField = FieldKey.nik }
                } label: {
                    Text("review.fillNIK")
                }
                .keyboardShortcut(.defaultAction)
                Button(action: onSave) { Text("review.saveAnyway") }
            }
            .sheet(isPresented: $expiryPickerShown) {
                ExpiryCalendar(title: expiryTitle) { review.setExpiry($0) }
            }
        }
    }

    /// "N halaman", then which page the fields came from and what other pages were read as, one text each.
    /// A page with a badge is said in amber like a mark, so it's seen when the screen is skimmed.
    private var pagesFooter: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("review.pages \(review.pages.count)")
            ForEach(review.pageNotes.lines, id: \.text) { line in
                if line.isMarked { WarningText(verbatim: line.text) } else { Text(verbatim: line.text) }
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

    @ViewBuilder private var validitySection: some View {
        if review.type == .ktp {
            Section {
                LabeledContent {
                    Text("review.forLife")
                } label: {
                    Text("review.validFor")
                }
            }
        } else if review.hasExpiry {
            Section {
                if let expiry = review.expiry, let shown = expiry.utcDate {
                    DatePicker(
                        selection: Binding(get: { shown }, set: { review.setExpiry(CalendarDate(utc: $0)) }),
                        displayedComponents: .date
                    ) {
                        expiryLabel
                    }
                    // Expiry dates are calendar days in UTC, so no time zone moves them.
                    .environment(\.timeZone, .gmt)
                    .accessibilityIdentifier("review.expiry")
                } else {
                    // Never shown as today: an empty expiry has to be seen, not saved quietly as none. The
                    // calendar sets nothing until Pilih, so opening it can't fill in a date by itself.
                    Button {
                        expiryPickerShown = true
                    } label: {
                        LabeledContent {
                            HStack(spacing: 6) {
                                Text("review.expiryMissing")
                                DisclosureChevron()
                            }
                        } label: {
                            expiryLabel
                        }
                    }
                    .accessibilityIdentifier("review.expiry")
                }
            } footer: {
                // The date printed on an STNK is its five-year validity; the one that matters is the tax.
                if review.type == .stnk { Text("review.taxHint") }
            }
        }
    }

    /// An STNK's date is its yearly tax; every other type's is its validity.
    private var expiryTitle: LocalizedStringResource {
        review.type == .stnk ? "review.taxValidUntil" : "review.validUntil"
    }

    private var expiryLabel: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(expiryTitle).foregroundStyle(Color.primary)
            if let note = review.expiryNote { WarningText(Self.text(for: note, numberKey: review.numberKey)) }
        }
    }
}

extension ReviewView {
    private static let labelFocus = "label"

    /// Simpan never quietly does nothing: a wrong value takes the user to its field, with a haptic, and
    /// VoiceOver reads the reason; an empty NIK is asked about first.
    private func trySave() {
        if let key = review.firstProblem() {
            focusedField = key
            refusals += 1
            // VoiceOver goes to the field and reads its label, which carries the reason.
            voiceOverField = key
        } else if review.nikMissing {
            nikMissingShown = true
        } else {
            onSave()
        }
    }

    /// Focus set while an alert is still closing can be dropped, so it waits until the alert is off the
    /// screen, checked rather than guessed with a delay. After two seconds at most it runs anyway.
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

    static func title(for key: String) -> LocalizedStringResource {
        switch key {
        case FieldKey.nik: "field.nik"
        case FieldKey.simNumber: "field.simNumber"
        case FieldKey.birthDate: "field.birthDate"
        default: "field.name"
        }
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
