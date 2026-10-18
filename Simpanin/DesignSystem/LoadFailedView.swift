//
//  LoadFailedView.swift
//  Simpanin
//
//  Created by Inez Amanda on 15/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

/// Shown instead of a list that couldn't load, so a failure never looks like an empty vault. It
/// only says the app changed nothing, which is true; it can't promise the documents are safe.
struct LoadFailedView: View {
    /// "Dokumen tidak bisa dimuat sekarang." unless a screen lists something else.
    var title: LocalizedStringResource = Self.title
    let onRetry: () -> Void

    nonisolated static let title = LocalizedStringResource("load.failedTitle")
    nonisolated static let message = LocalizedStringResource("load.failedBody")

    var body: some View {
        VStack(spacing: 16) {
            IconBadge(
                systemImage: "arrow.counterclockwise", size: 64, symbolFont: .system(size: 28, weight: .medium),
                tint: .primary, background: Color(.systemGray5))
            Text(title).font(.title3.bold()).multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text(Self.message).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button(action: onRetry) {
                Text(ScreenText.retry)
            }
            .buttonStyle(.prominent(fillsWidth: false))
            .accessibilityIdentifier("load.retry")
            .padding(.top, 8)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity)
        // A container, so the button keeps its own identifier.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("load.failed")
    }
}
