//
//  WatermarkRenderer.swift
//  Simpanin
//
//  Created by Inez Amanda on 4/11/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import CoreGraphics
import CoreText
import Foundation

/// Draws the mark into the page's own pixels: a new image, never a layer over the old one. Red with a thin
/// white outline, so it shows on a KTP's blue and on a dark page alike.
nonisolated enum WatermarkRenderer {
    static let fill = CGColor(srgbRed: 0.78, green: 0.06, blue: 0.1, alpha: 0.5)
    /// Faint, so it doesn't blur the page's text under it, yet enough to carry the mark on a dark page.
    static let outline = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.35)
    /// The outline's width, as a percentage of the font size (Core Text's unit).
    static let outlineWidth = 8

    static func marked(_ page: CGImage, text: String) -> CGImage? {
        let size = CGSize(width: page.width, height: page.height)
        guard
            let context = CGContext(
                data: nil, width: page.width, height: page.height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        context.draw(page, in: CGRect(origin: .zero, size: size))
        let layout = Watermark(text: text, pageSize: size)
        context.translateBy(x: size.width / 2, y: size.height / 2)
        context.scaleBy(x: layout.scale, y: layout.scale)
        context.rotate(by: Watermark.angle)
        let font = Watermark.font(size: layout.referenceFontSize)
        let key = { (name: CFString) in NSAttributedString.Key(name as String) }
        // The outline first, then the fill over it, so the white never covers the red.
        let passes: [[NSAttributedString.Key: Any]] = [
            [
                key(kCTFontAttributeName): font, key(kCTStrokeColorAttributeName): outline,
                key(kCTStrokeWidthAttributeName): outlineWidth,
            ],
            [key(kCTFontAttributeName): font, key(kCTForegroundColorAttributeName): fill],
        ]
        let descent = CTFontGetDescent(font)
        for attributes in passes {
            let lines = layout.lines.map {
                CTLineCreateWithAttributedString(NSAttributedString(string: $0, attributes: attributes))
            }
            for origin in layout.referenceOrigins {
                for (index, line) in lines.enumerated() {
                    let baseline = origin.y + CGFloat(lines.count - 1 - index) * layout.referenceLineHeight + descent
                    context.textPosition = CGPoint(x: origin.x, y: baseline)
                    CTLineDraw(line, context)
                }
            }
        }
        return context.makeImage()
    }
}
