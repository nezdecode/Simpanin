//
//  FullWidthButtonStyle.swift
//  Simpanin
//
//  Created by Inez Amanda on 15/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

/// The full-width button at the bottom of a screen. It builds on the system's prominent style, so
/// the button keeps its pressed and disabled looks and iOS 26's glass. Secondary is for a way out
/// that's a decision rather than the obvious next step, like "Mulai vault baru".
struct FullWidthButtonStyle: PrimitiveButtonStyle {
    enum Emphasis {
        case primary, secondary
    }

    var emphasis: Emphasis = .primary

    func makeBody(configuration: Configuration) -> some View {
        Button(role: configuration.role, action: configuration.trigger) {
            configuration.label
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 50)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.roundedRectangle(radius: 14))
        .tint(emphasis == .primary ? .accentColor : Color(.accentSoft))
        .foregroundStyle(emphasis == .primary ? AnyShapeStyle(.white) : AnyShapeStyle(Color(.onAccentSoft)))
    }
}

extension PrimitiveButtonStyle where Self == FullWidthButtonStyle {
    static var fullWidth: FullWidthButtonStyle { FullWidthButtonStyle() }

    static func fullWidth(_ emphasis: FullWidthButtonStyle.Emphasis) -> FullWidthButtonStyle {
        FullWidthButtonStyle(emphasis: emphasis)
    }
}
