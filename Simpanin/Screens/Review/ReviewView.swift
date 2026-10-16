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
            .navigationTitle(Text("review.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: onCancel) { Text(ScreenText.cancel) }
                        .accessibilityIdentifier("review.cancel")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(action: onRescan) { Text("review.rescan") }
                        .disabled(reading)
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
                    if review.typeNeedsCheck { CheckAgainText() }
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
            TextField(
                text: Binding(get: { review.values[key] ?? "" }, set: { review.setValue($0, for: key) })
            ) {
                Text(Self.title(for: key))
            }
            .keyboardType(Self.keyboard(for: key))
            .autocorrectionDisabled()
            .font(key == FieldKey.nik || key == FieldKey.simNumber ? .body.monospaced() : .body)
            .accessibilityIdentifier("review.field.\(key)")
            if review.marked.contains(key) { CheckAgainText() }
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
                DatePicker(
                    selection: Binding(
                        get: { review.expiry.flatMap { Calendar.gregorianUTC.date(from: $0.components) } ?? .now },
                        set: { date in
                            let parts = Calendar.gregorianUTC.dateComponents([.year, .month, .day], from: date)
                            review.setExpiry(
                                CalendarDate(year: parts.year ?? 0, month: parts.month ?? 0, day: parts.day ?? 0))
                        }),
                    displayedComponents: .date
                ) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("review.validUntil")
                        if review.expiryNeedsCheck { CheckAgainText() }
                    }
                }
                // Expiry dates are calendar days in UTC, so no time zone moves them.
                .environment(\.timeZone, .gmt)
                .accessibilityIdentifier("review.expiry")
            }
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

    private static func keyboard(for key: String) -> UIKeyboardType {
        switch key {
        case FieldKey.nik: .numberPad
        case FieldKey.simNumber, FieldKey.birthDate: .numbersAndPunctuation
        default: .default
        }
    }
}

/// "Periksa lagi" under a field the parser isn't sure about.
private struct CheckAgainText: View {
    var body: some View {
        Label {
            Text("review.checkAgain")
        } icon: {
            Image(systemName: "exclamationmark.triangle")
        }
        .font(.footnote)
        .foregroundStyle(Color(.warning))
    }
}
