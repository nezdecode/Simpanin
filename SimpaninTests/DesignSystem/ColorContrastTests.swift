//
//  ColorContrastTests.swift
//  SimpaninTests
//
//  Created by Inez Amanda on 19/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Testing
import UIKit

@testable import Simpanin

/// Text keeps a contrast of at least 4.5:1 in light and in dark mode (WCAG AA).
@Suite("Colour contrast")
struct ColorContrastTests {
    /// A refusal on its own ground, and a mark on a form row, where both are shown.
    @Test(arguments: [UIUserInterfaceStyle.light, .dark])
    func refusalsAndMarksKeepTheirContrast(_ style: UIUserInterfaceStyle) {
        let traits = UITraitCollection(userInterfaceStyle: style)
        let error = UIColor(resource: RefusalText.color).resolvedColor(with: traits)
        let errorGround = UIColor(resource: RefusalText.ground).resolvedColor(with: traits)
        let mark = UIColor(resource: WarningText.color).resolvedColor(with: traits)
        let row = UIColor.secondarySystemGroupedBackground.resolvedColor(with: traits)
        #expect(Self.contrast(error, errorGround) >= 4.5)
        #expect(Self.contrast(mark, row) >= 4.5)
    }

    /// The document screen's Berlaku status line, on its row: 15 pt isn't large text, so 4.5:1 holds.
    @Test(arguments: [UIUserInterfaceStyle.light, .dark])
    @MainActor func expiryStatusLinesKeepTheirContrast(_ style: UIUserInterfaceStyle) {
        let traits = UITraitCollection(userInterfaceStyle: style)
        let row = UIColor.secondarySystemGroupedBackground.resolvedColor(with: traits)
        for isExpired in [false, true] {
            let status = ValidityLines.Status(text: "expiry.today", isExpired: isExpired)
            let color = UIColor(resource: status.color).resolvedColor(with: traits)
            #expect(Self.contrast(color, row) >= 4.5, "expired: \(isExpired)")
        }
    }

    static func contrast(_ first: UIColor, _ second: UIColor) -> Double {
        let (lighter, darker) = (max(luminance(first), luminance(second)), min(luminance(first), luminance(second)))
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// Relative luminance, from sRGB.
    static func luminance(_ color: UIColor) -> Double {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: nil)
        func linear(_ value: CGFloat) -> Double {
            let value = Double(value)
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }
}
