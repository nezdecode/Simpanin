//
//  RefusalText.swift
//  Simpanin
//
//  Created by Inez Amanda on 19/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

/// Why something was refused: red with a circled "!" on a pale red ground, so it never reads like a mark
/// (`WarningText`, amber with a triangle), which can be left as it is.
struct RefusalText: View {
    let text: LocalizedStringResource

    init(_ text: LocalizedStringResource) { self.text = text }

    static let color = ColorResource.error
    static let ground = ColorResource.errorBackground

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: "exclamationmark.circle")
        }
        .font(.footnote)
        .foregroundStyle(Color(Self.color))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(Self.ground), in: .rect(cornerRadius: 6))
    }
}
