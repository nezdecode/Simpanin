//
//  GroupedRow.swift
//  Simpanin
//
//  Created by Inez Amanda on 14/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

/// A white row on the grouped background, like a table cell.
struct GroupedRow: View {
    let title: LocalizedStringResource
    var value: String = ""
    var systemImage: String?

    var body: some View {
        HStack(spacing: 12) {
            if let systemImage { Image(systemName: systemImage).foregroundStyle(.secondary).accessibilityHidden(true) }
            Text(title)
            Spacer()
            Text(verbatim: value).foregroundStyle(.secondary)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 50)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 12))
        .contentShape(.rect)
    }
}
