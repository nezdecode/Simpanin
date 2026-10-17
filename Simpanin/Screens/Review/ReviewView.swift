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
                Section { pagesRow }
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
            // The number pad has no return key: Selesai above it, or a swipe down the form, closes it.
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(Text("review.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Only the number pad needs it: every other keyboard has Return.
                ToolbarItemGroup(placement: .keyboard) {
                    if let focusedField, Self.keyboard(for: focusedField) == .numberPad {
                        Spacer()
                        Button {
                            self.focusedField = nil
                        } label: {
                            Text(ScreenText.done)
                        }
                        .accessibilityIdentifier("keyboard.done")
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    // Nothing can be cancelled or rescanned while a save is being written.
                    Button(action: onCancel) { Text(ScreenText.cancel) }
                        .disabled(review.saving)
                        .accessibilityIdentifier("review.cancel")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(action: onRescan) { Text("review.rescan") }
                        .disabled(reading || review.saving)
                        .accessibilityIdentifier("review.rescan")
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
                    focusedField = FieldKey.nik
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

    private var pagesRow: some View {
        HStack(spacing: 14) {
            if let first = review.pages.first {
                Image(decorative: first, scale: 1)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 112, height: 72)
                    .clipShape(.rect(cornerRadius: 10))
            }
            Text("review.pages \(review.pages.count)").font(.headline)
        }
    }

    private var typeRow: some View {
        Button {
            typePickerShown = true
        } label: {
            LabeledContent {
                HStack(spacing: 6) {
                    Text(DocumentStyle.name(review.type))
                    opensSheet
                }
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("review.type").foregroundStyle(Color.primary)
                    if review.typeNeedsCheck { WarningText("review.checkAgain") }
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
                .foregroundStyle(Color(.warning))
                .accessibilityIdentifier("review.labelIsNumber")
            } else {
                Text("review.labelHint")
            }
        }
    }

    private func fieldRow(_ key: String) -> some View {
        FieldRow(
            key: key, value: review.values[key] ?? "", isLast: key == review.fieldKeys.last,
            warning: review.problems[key].map(Self.reason) ?? (review.marked.contains(key) ? "review.checkAgain" : nil),
            refusal: review.problems[key].map(Self.reason), focus: $focusedField, voiceOverFocus: $voiceOverField,
            onChange: { review.setValue($0, for: key) }, onSubmit: { focusField(after: key) })
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
                                opensSheet
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

    /// The chevron of a row that opens a sheet, as in Settings, so the row reads as something to tap.
    private var opensSheet: some View {
        Image(systemName: "chevron.forward")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)
    }

    private var expiryLabel: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(expiryTitle).foregroundStyle(Color.primary)
            if review.expiryNeedsCheck || review.marksMissingExpiry { WarningText("review.checkAgain") }
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
            // VoiceOver goes to the field and reads its value, which carries the reason.
            voiceOverField = key
            AccessibilityNotification.LayoutChanged().post()
        } else if review.nikMissing {
            nikMissingShown = true
        } else {
            onSave()
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

    private static func reason(for problem: ReviewModel.FieldProblem) -> LocalizedStringResource {
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
