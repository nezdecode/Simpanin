//
//  ProminentButtonStyle.swift
//  Simpanin
//
//  Created by Inez Amanda on 14/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

/// The app's main button. It builds on the system's prominent style, so the button keeps its
/// pressed and disabled looks and iOS 26's glass. It fills the width at the bottom of a screen, or
/// fits its title inside a state like "Dokumen tidak bisa dimuat". Secondary is for a way out
/// that's a decision rather than the obvious next step, like "Mulai vault baru".
struct ProminentButtonStyle: PrimitiveButtonStyle {
    enum Emphasis {
        case primary, secondary
    }

    var emphasis: Emphasis = .primary
    var fillsWidth = true

    func makeBody(configuration: Configuration) -> some View {
        Button(role: configuration.role, action: configuration.trigger) {
            configuration.label
                .font(.headline)
                .padding(.horizontal, fillsWidth ? 0 : 16)
                .frame(maxWidth: fillsWidth ? .infinity : nil, minHeight: 50)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.roundedRectangle(radius: 14))
        .tint(emphasis == .primary ? .accentColor : Color(.accentSoft))
        .foregroundStyle(emphasis == .primary ? Color(.onAccent) : Color(.onAccentSoft))
    }
}

extension PrimitiveButtonStyle where Self == ProminentButtonStyle {
    static var prominent: ProminentButtonStyle { ProminentButtonStyle() }

    static func prominent(
        _ emphasis: ProminentButtonStyle.Emphasis = .primary, fillsWidth: Bool = true
    ) -> ProminentButtonStyle {
        ProminentButtonStyle(emphasis: emphasis, fillsWidth: fillsWidth)
    }
}
