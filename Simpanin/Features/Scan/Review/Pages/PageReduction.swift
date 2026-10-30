//
//  PageReduction.swift
//  Simpanin
//
//  Created by Inez Amanda on 30/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import CoreGraphics

/// A scanned page redrawn at most `longSide` pixels on its longer side, keeping its shape; never larger than
/// it was. The scan is already a bitmap, so there's no data for ImageIO's thumbnail call to read from. The
/// context's format is fixed, never the page's own, so only a lack of memory can make it fail.
nonisolated func reducedPage(_ page: CGImage, longSide: Int) -> CGImage? {
    let scale = min(1, Double(longSide) / Double(max(page.width, page.height)))
    guard scale < 1 else { return page }
    let width = max(1, Int((Double(page.width) * scale).rounded()))
    let height = max(1, Int((Double(page.height) * scale).rounded()))
    guard let sRGB = CGColorSpace(name: CGColorSpace.sRGB),
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
    else { return nil }
    context.interpolationQuality = .high
    context.draw(page, in: CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()
}
