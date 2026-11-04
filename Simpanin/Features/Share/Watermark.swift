//
//  Watermark.swift
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
import UIKit

/// Where the mark goes on a page: one block of at most two lines, repeated in offset rows across the whole
/// page at an angle, over the NIK and the photo too, so cropping can't leave either clean. Every length is a
/// share of the page's longer side, so the preview and the copy are the same layout at two sizes.
///
/// The system font changes its shapes and spacing with its size, so text measured at 30 and at 80 points
/// doesn't scale in proportion. The layout is made once on a page of `referenceLongSide` and drawn scaled.
nonisolated struct Watermark: Equatable {
    /// Rising to the right, in a frame whose y axis points up, as Core Graphics draws.
    static let angle = 22 * CGFloat.pi / 180
    /// Small and spread out, so the page's own text stays readable between the rows (chosen on a KTP).
    static let fontShare: CGFloat = 0.02
    static let widthShare: CGFloat = 0.5
    static let referenceLongSide: CGFloat = 3000

    let pageSize: CGSize
    /// Page pixels per reference pixel.
    let scale: CGFloat
    let lines: [String]
    let referenceFontSize: CGFloat
    let referenceBlockSize: CGSize
    /// Each block's bottom left corner, in the reference frame: rotated, with its origin at the page's centre.
    let referenceOrigins: [CGPoint]

    var referenceLineHeight: CGFloat { referenceFontSize * 1.25 }
    var fontSize: CGFloat { referenceFontSize * scale }
    /// The block's size in the rotated frame, in page pixels.
    var blockSize: CGSize {
        CGSize(width: referenceBlockSize.width * scale, height: referenceBlockSize.height * scale)
    }
    var origins: [CGPoint] { referenceOrigins.map { CGPoint(x: $0.x * scale, y: $0.y * scale) } }

    init(text: String, pageSize: CGSize) {
        self.pageSize = pageSize
        let longSide = max(pageSize.width, pageSize.height, 1)
        scale = longSide / Self.referenceLongSide
        let reference = CGSize(width: pageSize.width / scale, height: pageSize.height / scale)
        let maxWidth = Self.referenceLongSide * Self.widthShare
        var size = Self.referenceLongSide * Self.fontShare
        var lines = Self.wrap(text, size: size, width: maxWidth)
        // Sixty characters and the date fit in two lines; anything longer gets a smaller mark, never a cut.
        for _ in 0..<20 where lines.count > 2 {
            size *= 0.9
            lines = Self.wrap(text, size: size, width: maxWidth)
        }
        referenceFontSize = size
        self.lines = lines
        let width = lines.map { Self.width(of: $0, size: size) }.max() ?? 0
        referenceBlockSize = CGSize(width: width, height: size * 1.25 * CGFloat(lines.count))
        referenceOrigins = Self.tile(block: referenceBlockSize, fontSize: size, pageSize: reference)
    }

    /// Offset rows of blocks over a circle around the page, so the rotated rows reach every corner.
    private static func tile(block: CGSize, fontSize: CGFloat, pageSize: CGSize) -> [CGPoint] {
        guard block.width > 0 else { return [] }
        let radius = hypot(pageSize.width, pageSize.height) / 2
        let across = block.width + fontSize * 4
        let down = block.height + fontSize * 5.5
        var origins: [CGPoint] = []
        var row = 0
        var rowY = -radius
        while rowY <= radius {
            var blockX = -radius - (row.isMultiple(of: 2) ? 0 : across / 2)
            while blockX <= radius {
                origins.append(CGPoint(x: blockX, y: rowY))
                blockX += across
            }
            rowY += down
            row += 1
        }
        return origins
    }

    /// Breaks at spaces where it can, and inside a word only when the word alone is too wide.
    private static func wrap(_ text: String, size: CGFloat, width: CGFloat) -> [String] {
        let string = text as NSString
        let typesetter = CTTypesetterCreateWithAttributedString(attributed(text, size: size))
        var lines: [String] = []
        var start = 0
        while start < string.length {
            var count = CTTypesetterSuggestLineBreak(typesetter, start, Double(width))
            let candidate = string.substring(with: NSRange(location: start, length: count))
            if Self.width(of: candidate.trimmingCharacters(in: .whitespaces), size: size) > width {
                count = CTTypesetterSuggestClusterBreak(typesetter, start, Double(width))
            }
            count = max(count, 1)
            let line = string.substring(with: NSRange(location: start, length: count))
            lines.append(line.trimmingCharacters(in: .whitespaces))
            start += count
        }
        return lines.filter { !$0.isEmpty }
    }

    static func attributed(_ text: String, size: CGFloat) -> NSAttributedString {
        NSAttributedString(
            string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font(size: size)])
    }

    private static func width(of line: String, size: CGFloat) -> CGFloat {
        CGFloat(
            CTLineGetTypographicBounds(CTLineCreateWithAttributedString(attributed(line, size: size)), nil, nil, nil))
    }

    static func font(size: CGFloat) -> CTFont {
        UIFont.systemFont(ofSize: size, weight: .semibold) as CTFont
    }
}
