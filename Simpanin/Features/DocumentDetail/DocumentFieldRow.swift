//
//  DocumentFieldRow.swift
//  Simpanin
//
//  Created by Inez Amanda on 28/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI
import VaultCore

/// One field of an opened document. A number comes masked, with an eye to show it; tapping the number
/// does the same. The masked text is all there is: the hidden digits are in no label or value.
struct DocumentFieldRow: View {
    let field: DocumentDetailModel.Field
    let numberShown: Bool
    let onToggleNumber: () -> Void
    let onCopy: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // At the accessibility sizes the buttons go under the text, which then has the full width.
        let layout =
            typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout(spacing: 4))
        layout {
            if field.isNumber, field.value != nil {
                // VoiceOver has the eye button for this, so the text stays one plain element.
                content.contentShape(.rect).onTapGesture(perform: onToggleNumber)
            } else {
                content
            }
            if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
            HStack(spacing: 4) {
                if field.isNumber, field.value != nil {
                    iconButton(numberShown ? "eye.slash" : "eye", label: toggleLabel, action: onToggleNumber)
                        .accessibilityIdentifier("detail.reveal")
                }
                if field.canCopy {
                    iconButton("doc.on.doc", label: copyLabel, action: onCopy)
                        .accessibilityIdentifier("detail.copy.\(field.key)")
                }
            }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(field.title).font(.subheadline).foregroundStyle(.secondary)
            if let value = field.value {
                Text(verbatim: value)
                    .font(field.isNumber ? .body.monospacedDigit() : .body)
            } else {
                Text(field.empty).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .multilineTextAlignment(.leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(field.title))
        .accessibilityValue(accessibilityValue)
        .accessibilityIdentifier("detail.field.\(field.key)")
    }

    private var accessibilityValue: Text {
        guard let value = field.value else { return Text(field.empty) }
        guard field.isNumber else { return Text(verbatim: value) }
        // Masked, the bullets would be read one by one; shown, the number is read digit by digit.
        return numberShown ? Text(verbatim: value).speechSpellsOutCharacters() : Text("detail.hidden")
    }

    private var toggleLabel: LocalizedStringResource {
        switch (field.key, numberShown) {
        case (FieldKey.simNumber, false): "detail.showSIMNumber"
        case (FieldKey.simNumber, true): "detail.hideSIMNumber"
        case (_, false): "detail.showNIK"
        case (_, true): "detail.hideNIK"
        }
    }

    private var copyLabel: LocalizedStringResource {
        switch field.key {
        case FieldKey.nik: "detail.copyNIK"
        case FieldKey.simNumber: "detail.copySIMNumber"
        default: "detail.copyName"
        }
    }

    private func iconButton(
        _ systemImage: String, label: LocalizedStringResource, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label {
                Text(label)
            } icon: {
                Image(systemName: systemImage)
            }
            .labelStyle(.iconOnly)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.borderless)
    }
}
