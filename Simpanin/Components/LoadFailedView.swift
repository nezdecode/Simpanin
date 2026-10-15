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
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            IconBadge(
                systemImage: "arrow.counterclockwise", size: 64, symbolFont: .system(size: 28, weight: .medium),
                tint: .primary, background: Color(.systemGray5))
            Text("load.failedTitle").font(.title3.bold()).multilineTextAlignment(.center)
            Text("load.failedBody").foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button(action: onRetry) {
                Text(ScreenText.retry).font(.headline).padding(.horizontal, 16)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 14))
            .controlSize(.large)
            .foregroundStyle(Color(.onAccent))
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
