//
//  IconBadge.swift
//  Simpanin
//
//  Created by Inez Amanda on 14/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

/// A symbol in a tinted circle or rounded square, in front of a row or at the top of a screen.
/// Decorative, so VoiceOver skips it; the text next to it says what it means.
struct IconBadge: View {
    enum Outline {
        case circle
        case roundedRectangle(cornerRadius: CGFloat)
    }

    let systemImage: String
    var size: CGFloat = 36
    /// nil keeps the surrounding font.
    var symbolFont: Font?
    let tint: Color
    let background: Color
    var outline: Outline = .circle

    var body: some View {
        let image = Image(systemName: systemImage)
            .font(symbolFont)
            .foregroundStyle(tint)
            .frame(width: size, height: size)
        Group {
            switch outline {
            case .circle: image.background(background, in: .circle)
            case .roundedRectangle(let radius): image.background(background, in: .rect(cornerRadius: radius))
            }
        }
        .accessibilityHidden(true)
    }
}
