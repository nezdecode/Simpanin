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
    /// What the calendar shows until Pilih; only then does it become the expiry.
    @State private var expiryDraft = Date.now

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
            // The number pad has no return key: Selesai above it, or a swipe down the form, closes it.
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(Text("review.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button {
                        focusedField = nil
                    } label: {
                        Text(ScreenText.done)
                    }
                    .accessibilityIdentifier("keyboard.done")
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
            .safeAreaInset(edge: .bottom) {
                Button(action: onSave) { Text("review.save") }
                    .buttonStyle(.prominent)
                    .disabled(reading || review.saving)
                    .padding(16)
                    .accessibilityIdentifier("review.save")
            }
            .sheet(isPresented: $typePickerShown) {
                TypePickerView(selection: $review.type)
            }
            .sheet(isPresented: $expiryPickerShown) { expiryPicker }
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
                Text(DocumentStyle.name(review.type))
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
            .autocorrectionDisabled()
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
                        expiryDraft = CalendarDate.today.utcDate ?? .now
                        expiryPickerShown = true
                    } label: {
                        LabeledContent {
                            Text("review.expiryMissing")
                        } label: {
                            expiryLabel
                        }
                    }
                    .accessibilityIdentifier("review.expiry")
                }
            }
        }
    }

    private var expiryPicker: some View {
        NavigationStack {
            DatePicker(selection: $expiryDraft, displayedComponents: .date) {
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
                        expiryPickerShown = false
                    } label: {
                        Text(ScreenText.cancel)
                    }
                    .accessibilityIdentifier("review.expiryCancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        review.setExpiry(CalendarDate(utc: expiryDraft))
                        expiryPickerShown = false
                    } label: {
                        Text("review.pickDate")
                    }
                    .accessibilityIdentifier("review.expiryPick")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var expiryLabel: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("review.validUntil").foregroundStyle(Color.primary)
            if review.expiryNeedsCheck || review.expiryMissing { WarningText("review.checkAgain") }
        }
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
