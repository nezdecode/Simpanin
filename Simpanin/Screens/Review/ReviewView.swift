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
    @FocusState private var focusedField: String?

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
                    Button(action: onSave) { Text("review.save") }
                        .buttonStyle(.prominent)
                        .disabled(reading || review.saving)
                        .padding(16)
                        .accessibilityIdentifier("review.save")
                }
            }
            .sheet(isPresented: $typePickerShown) {
                TypePickerView(selection: $review.type)
            }
            .sheet(isPresented: $expiryPickerShown) {
                ExpiryCalendar { review.setExpiry($0) }
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
        VStack(alignment: .leading, spacing: 4) {
            Text(Self.title(for: key)).font(.footnote).foregroundStyle(.secondary)
            Group {
                if ReviewModel.dateKeys.contains(key) {
                    DateField(title: Self.title(for: key), value: review.values[key] ?? "") {
                        review.setValue($0, for: key)
                    }
                } else {
                    TextField(
                        text: Binding(get: { review.values[key] ?? "" }, set: { review.setValue($0, for: key) })
                    ) {
                        Text(Self.title(for: key))
                    }
                }
            }
            .focused($focusedField, equals: key)
            .keyboardType(Self.keyboard(for: key))
            // Nothing typed here is corrected or learned by the keyboard, so a name isn't "fixed" and no
            // value comes back as a suggestion in another app.
            .autocorrectionDisabled()
            .textInputAutocapitalization(key == FieldKey.name ? .characters : .never)
            .submitLabel(key == review.fieldKeys.last ? .done : .next)
            .onSubmit { focusField(after: key) }
            .font(key == FieldKey.nik || key == FieldKey.simNumber ? .body.monospaced() : .body)
            .accessibilityIdentifier("review.field.\(key)")
            if let problem = review.problems[key] {
                WarningText(Self.reason(for: problem))
            } else if review.marked.contains(key) {
                WarningText("review.checkAgain")
            }
        }
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
            }
        }
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
            Text("review.validUntil").foregroundStyle(Color.primary)
            if review.expiryNeedsCheck || review.expiryMissing { WarningText("review.checkAgain") }
        }
    }

    private static let labelFocus = "label"

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
        }
    }

    private static func keyboard(for key: String) -> UIKeyboardType {
        switch key {
        case FieldKey.nik: .numberPad
        case FieldKey.birthDate: .numberPad
        case FieldKey.simNumber: .numbersAndPunctuation
        default: .default
        }
    }
}

/// The calendar for an expiry that wasn't read. It starts on today but sets nothing until Pilih.
private struct ExpiryCalendar: View {
    let onPick: (CalendarDate?) -> Void
    @State private var draft = CalendarDate.today.utcDate ?? .now
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            DatePicker(selection: $draft, displayedComponents: .date) {
                Text("review.validUntil")
            }
            .datePickerStyle(.graphical)
            // Expiry dates are calendar days in UTC, so no time zone moves them.
            .environment(\.timeZone, .gmt)
            .padding(.horizontal)
            .navigationTitle(Text("review.validUntil"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text(ScreenText.cancel)
                    }
                    .accessibilityIdentifier("review.expiryCancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onPick(CalendarDate(utc: draft))
                        dismiss()
                    } label: {
                        Text("review.pickDate")
                    }
                    .accessibilityIdentifier("review.expiryPick")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// A dd-mm-yyyy field for the number pad. A binding whose setter reformats doesn't update what the field
/// shows when the model's value stays the same, so digits typed past the eighth stayed on screen; the
/// field keeps its own draft and writes the formatted text back into it.
private struct DateField: View {
    let title: LocalizedStringResource
    let value: String
    let onChange: (String) -> Void
    @State private var draft = ""

    var body: some View {
        TextField(text: $draft, prompt: Text("review.datePlaceholder")) {
            Text(title)
        }
        .onAppear { draft = value }
        .onChange(of: draft) { _, typed in
            let formatted = ReviewModel.typedDate(typed)
            if formatted != typed { draft = formatted }
            if formatted != value { onChange(formatted) }
        }
        // A rescan replaces the value from outside.
        .onChange(of: value) { _, new in
            if new != draft { draft = new }
        }
    }
}

/// Under a field: "Periksa lagi" when the parser isn't sure, or why Simpan refused it.
private struct WarningText: View {
    let text: LocalizedStringResource

    init(_ text: LocalizedStringResource) { self.text = text }

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: "exclamationmark.triangle")
        }
        .font(.footnote)
        .foregroundStyle(Color(.warning))
    }
}
