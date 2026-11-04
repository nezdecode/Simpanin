//
//  WatermarkTests.swift
//  SimpaninTests
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
import Testing

@testable import Simpanin

@Suite("Watermark")
struct WatermarkTests {
    static let mark = "Sewa kos Jl. Perintis · 4 Nov 2026"

    func width(_ line: String, _ layout: Watermark) -> CGFloat {
        let attributed = NSAttributedString(
            string: line,
            attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): Watermark.font(
                    size: layout.referenceFontSize)
            ])
        return CTLineGetTypographicBounds(CTLineCreateWithAttributedString(attributed), nil, nil, nil)
    }

    @Test func theMarkScalesWithThePage() {
        let landscape = Watermark(text: Self.mark, pageSize: CGSize(width: 3000, height: 2000))
        let portrait = Watermark(text: Self.mark, pageSize: CGSize(width: 2000, height: 3000))
        let tiny = Watermark(text: Self.mark, pageSize: CGSize(width: 120, height: 80))
        #expect(landscape.fontSize > 0)
        #expect(abs(portrait.fontSize - landscape.fontSize) < 0.001)
        #expect(abs(tiny.fontSize * 25 - landscape.fontSize) < 0.01)
        for layout in [landscape, portrait, tiny] {
            #expect(!layout.origins.isEmpty)
            #expect(layout.lines == [Self.mark])
        }
    }

    @Test func aLongPurposeWrapsToTwoLines() {
        let purpose = "Pembukaan rekening tabungan di BCA KCP Sudirman untuk gaji kantor"
        let text = SharePurpose.mark(purpose: purpose, date: .now, timeZone: .current)
        let layout = Watermark(text: text, pageSize: CGSize(width: 3000, height: 2000))
        #expect(layout.lines.count == 2)
        #expect(layout.lines.joined(separator: " ") == text)
        for line in layout.lines { #expect(width(line, layout) <= layout.referenceBlockSize.width + 0.5) }
    }

    @Test func aLongWordBreaksByCharacter() {
        let word = String(repeating: "Perintis", count: 7) + "1234"
        let text = word + " · 4 Nov 2026"
        let layout = Watermark(text: text, pageSize: CGSize(width: 3000, height: 2000))
        #expect(layout.lines.count == 2)
        #expect(
            layout.lines.joined().replacingOccurrences(of: " ", with: "")
                == text.replacingOccurrences(
                    of: " ", with: ""))
        for line in layout.lines { #expect(width(line, layout) <= layout.referenceBlockSize.width + 0.5) }
    }

    /// The preview is drawn at 1200 px and the copy at up to 3000: the same layout, scaled.
    @Test func thePreviewAndTheCopyUseTheSameLayout() {
        let text = SharePurpose.mark(
            purpose: "Pembukaan rekening tabungan di BCA KCP Sudirman", date: .now, timeZone: .current)
        let preview = Watermark(text: text, pageSize: CGSize(width: 1200, height: 757))
        let copy = Watermark(text: text, pageSize: CGSize(width: 3000, height: 1892.5))
        let scale: CGFloat = 2.5
        #expect(preview.lines == copy.lines)
        #expect(abs(preview.fontSize * scale - copy.fontSize) < 0.01)
        #expect(preview.origins.count == copy.origins.count)
        for (small, large) in zip(preview.origins, copy.origins) {
            #expect(abs(small.x * scale - large.x) < 0.5 && abs(small.y * scale - large.y) < 0.5)
        }
    }
}

@Suite("Watermark renderer")
struct WatermarkRendererTests {
    /// RGBA bytes of an image, to look at what was drawn.
    struct Pixels {
        let width: Int
        let height: Int
        let bytes: [UInt8]

        init(_ image: CGImage) throws {
            let width = image.width
            let height = image.height
            var buffer = [UInt8](repeating: 0, count: width * height * 4)
            let drawn = buffer.withUnsafeMutableBytes { raw -> Bool in
                guard
                    let context = CGContext(
                        data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                        bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
                else { return false }
                context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
                return true
            }
            try #require(drawn)
            self.width = width
            self.height = height
            bytes = buffer
        }

        func luminance(x pixelX: Int, y pixelY: Int) -> Double {
            let index = (pixelY * width + pixelX) * 4
            return
                (0.2126 * Double(bytes[index]) + 0.7152 * Double(bytes[index + 1])
                + 0.0722 * Double(bytes[index + 2])) / 255
        }

        /// The largest luminance difference from `ground` in each cell of a grid.
        func strongestDifference(from ground: Double, columns: Int, rows: Int) -> [Double] {
            var cells: [Double] = []
            for row in 0..<rows {
                for column in 0..<columns {
                    var strongest = 0.0
                    for pixelY in stride(from: row * height / rows, to: (row + 1) * height / rows, by: 2) {
                        for pixelX in stride(from: column * width / columns, to: (column + 1) * width / columns, by: 2)
                        {
                            strongest = max(strongest, abs(luminance(x: pixelX, y: pixelY) - ground))
                        }
                    }
                    cells.append(strongest)
                }
            }
            return cells
        }
    }

    func page(gray: CGFloat, width: Int = 1200, height: Int = 757) throws -> CGImage {
        let context = try #require(
            CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 4 * width,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(red: gray, green: gray, blue: gray, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try #require(context.makeImage())
    }

    @Test func theMarkCoversEveryPartOfThePage() throws {
        let marked = try #require(WatermarkRenderer.marked(try page(gray: 1), text: WatermarkTests.mark))
        #expect(marked.width == 1200 && marked.height == 757)
        let cells = try Pixels(marked).strongestDifference(from: 1, columns: 6, rows: 4)
        #expect(cells.allSatisfy { $0 > 0.1 })
    }

    /// Red alone turns a low-contrast purple on a KTP's blue and nearly vanishes on a dark page; the white
    /// outline carries it there.
    @Test func theMarkStaysVisibleOnALightAndADarkPage() throws {
        for gray in [1.0, 0.0, 0.25] {
            let marked = try #require(WatermarkRenderer.marked(try page(gray: gray), text: WatermarkTests.mark))
            let cells = try Pixels(marked).strongestDifference(from: gray, columns: 4, rows: 3)
            #expect(cells.allSatisfy { $0 >= 0.2 }, "page at \(gray)")
        }
    }
}
