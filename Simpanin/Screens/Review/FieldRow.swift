//
//  FieldRow.swift
//  Simpanin
//
//  Created by Inez Amanda on 17/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI
import VaultCore

/// One field of the document: its title, the value, and under it why Simpan refused it or "Periksa lagi".
struct FieldRow: View {
    let key: String
    let value: String
    let isLast: Bool
    let warning: LocalizedStringResource?
    /// Why Simpan refused the value, read by VoiceOver with the field's name.
    let refusal: LocalizedStringResource?
    var focus: FocusState<String?>.Binding
    var voiceOverFocus: AccessibilityFocusState<String?>.Binding
    let onChange: (String) -> Void
    let onSubmit: () -> Void

    private var title: String { String(localized: ReviewView.title(for: key)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(ReviewView.title(for: key)).font(.footnote).foregroundStyle(.secondary)
            Group {
                if ReviewModel.dateKeys.contains(key) {
                    DateField(title: ReviewView.title(for: key), value: value, onChange: onChange)
                } else {
                    TextField(text: Binding(get: { value }, set: { onChange($0) })) {
                        Text(ReviewView.title(for: key))
                    }
                }
            }
            .focused(focus, equals: key)
            .keyboardType(ReviewView.keyboard(for: key))
            // Nothing typed here is corrected or learned by the keyboard, so a name isn't "fixed" and no
            // value comes back as a suggestion in another app.
            .autocorrectionDisabled()
            .textInputAutocapitalization(key == FieldKey.name ? .characters : .never)
            .submitLabel(isLast ? .done : .next)
            .onSubmit(onSubmit)
            .font(key == FieldKey.nik || key == FieldKey.simNumber ? .body.monospaced() : .body)
            // In the label, not a hint: hints can be turned off and are often cut short. A TextField ignores
            // accessibilityValue (its value is always the text), so the reason goes with the field's name.
            .accessibilityLabel(
                refusal.map { Text("review.labelWithReason \(title) \(String(localized: $0))") } ?? Text(title)
            )
            .accessibilityFocused(voiceOverFocus, equals: key)
            .accessibilityIdentifier("review.field.\(key)")
            if let warning { WarningText(warning) }
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
