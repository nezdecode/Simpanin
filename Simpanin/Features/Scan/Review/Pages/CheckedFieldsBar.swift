//
//  CheckedFieldsBar.swift
//  Simpanin
//
//  Created by Inez Amanda on 30/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

/// Under an enlarged page: the fields to compare with the card, so 16 digits needn't be remembered across the
/// viewer. Plain text, never selectable, so nothing here reaches the clipboard.
struct CheckedFieldsBar: View {
    let fields: [ReviewModel.CheckedField]
    @ScaledMetric(relativeTo: .body) private var maxHeight = 170

    var body: some View {
        // Past about three rows it scrolls within its height, so the page keeps its room and no field is dropped.
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(fields, id: \.key) { field in row(field) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxHeight: maxHeight)
        .fixedSize(horizontal: false, vertical: true)
        .background(.regularMaterial)
        // The viewer is black in light and dark alike, so the bar is too.
        .environment(\.colorScheme, .dark)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .accessibilityIdentifier("viewer.checkedFields")
    }

    private func row(_ field: ReviewModel.CheckedField) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(field.title).font(.footnote).foregroundStyle(.secondary)
            Group {
                if let value = field.value {
                    // Digit by digit for VoiceOver, as they're compared one by one; a name reads as a name.
                    Text(verbatim: value).speechSpellsOutCharacters(field.isNumber)
                } else {
                    Text("review.expiryMissing").foregroundStyle(.secondary)
                }
            }
            .font(field.isNumber ? .body.monospaced() : .body)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("viewer.checkedField.\(field.key)")
    }
}

extension View {
    /// The bar under the enlarged page, left out when there's nothing to compare.
    func checkedFieldsBar(_ fields: [ReviewModel.CheckedField]) -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            if !fields.isEmpty { CheckedFieldsBar(fields: fields) }
        }
    }
}
