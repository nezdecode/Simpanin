//
//  DocumentFormSections.swift
//  Simpanin
//
//  Created by Inez Amanda on 5/11/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI
import VaultCore

/// The label and the fields, as Periksa data and Edit dokumen show them, so the two never drift apart.
/// Return moves to the next field, in the order shown; after the last, the keyboard closes.
struct DocumentFormSections: View {
    /// The label's focus value; the fields use their keys.
    static let labelFocus = "label"

    @Binding var label: String
    let form: DocumentForm
    /// "Cocok dengan tanggal lahir" under the number.
    let showsBirthDateMatch: Bool
    var focus: FocusState<String?>.Binding
    var voiceOverFocus: AccessibilityFocusState<String?>.Binding
    let onChange: (_ text: String, _ key: String) -> Void

    var body: some View {
        labelSection
        if !form.fieldKeys.isEmpty {
            Section {
                ForEach(form.fieldKeys, id: \.self) { key in fieldRow(key) }
            }
        }
    }

    private var labelSection: some View {
        Section {
            TextField(text: $label, prompt: Text("review.labelPlaceholder")) {
                Text("review.label")
            }
            .focused(focus, equals: Self.labelFocus)
            .autocorrectionDisabled()
            .submitLabel(.next)
            .onSubmit { focusField(after: Self.labelFocus) }
            .accessibilityIdentifier("review.label")
        } header: {
            Text("review.label")
        } footer: {
            if DocumentForm.looksLikeANumber(label) {
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
        let note = form.note(for: key)
        var refusal: LocalizedStringResource?
        var markReason: LocalizedStringResource?
        if case .refusal(let problem) = note { refusal = FormText.reason(for: problem) }
        if case .mark(let reason?) = note { markReason = FormText.reasonText(reason, numberKey: form.numberKey) }
        let match = showsBirthDateMatch && key == form.numberKey
        return FieldRow(
            key: key, value: form.values[key] ?? "", isLast: key == form.fieldKeys.last, refusal: refusal,
            markReason: markReason, footnote: match ? "review.birthDateMatch" : nil, focus: focus,
            voiceOverFocus: voiceOverFocus, onChange: { onChange($0, key) },
            onSubmit: { focusField(after: key) })
    }

    private func focusField(after current: String) {
        let order = [Self.labelFocus] + form.fieldKeys
        guard let index = order.firstIndex(of: current), index + 1 < order.count else {
            focus.wrappedValue = nil
            return
        }
        focus.wrappedValue = order[index + 1]
    }
}
