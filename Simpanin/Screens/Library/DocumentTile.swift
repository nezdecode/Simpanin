//
//  DocumentTile.swift
//  Simpanin
//
//  Created by Inez Amanda on 14/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI
import VaultCore

/// A document on the list: its type and expiry, in the type's colors.
struct DocumentTile: View {
    let document: VaultCore.Document
    let today: CalendarDate
    let wide: Bool

    var body: some View {
        let colors = DocumentStyle.tileColors(document.type)
        VStack(alignment: .leading, spacing: 6) {
            Text(DocumentStyle.name(document.type))
                .font(.footnote.weight(.bold))
                .tracking(0.6)
            Spacer(minLength: wide ? 0 : 12)
            if let label = DocumentStyle.shownLabel(document.label) {
                Text(verbatim: label).font(.headline).lineLimit(1)
            }
            Text(ExpiryText.text(type: document.type, expiry: document.expiry, today: today))
                .font(.footnote)
        }
        .foregroundStyle(Color(colors.foreground))
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: wide ? 0 : 104, alignment: .leading)
        .background(Color(colors.background), in: .rect(cornerRadius: 18))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("document.row")
    }
}
