//
//  PageThumbnailTests.swift
//  SimpaninTests
//
//  Created by Inez Amanda on 30/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import CoreGraphics
import Testing

@testable import Simpanin

@Suite("Page thumbnails")
struct PageThumbnailTests {
    func page(width: Int, height: Int) throws -> CGImage {
        let context = try #require(
            CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 4 * width,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        return try #require(context.makeImage())
    }

    /// The strip's size is a memory rule too, so it's pinned here rather than read from the constant.
    @Test func thumbnailsAreAtMost600PixelsLong() async throws {
        let pages = [try page(width: 2_400, height: 1_800), try page(width: 900, height: 1_800)]
        let thumbnails = await PageThumbnail.made(of: pages)
        #expect(thumbnails.map { $0.image.map { max($0.width, $0.height) } } == [600, 600])
    }

    /// The lock cancels the scan; the full-size pages aren't held on to while the rest are redrawn.
    @Test func aCancelledScanStopsMakingThumbnails() async throws {
        let pages = [try page(width: 10, height: 10), try page(width: 10, height: 10)]
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            var reduced = 0
            let thumbnails = PageThumbnail.thumbnails(of: pages) { page, _ in
                reduced += 1
                return page
            }
            return (thumbnails.count, reduced)
        }
        let (made, reduced) = await task.value
        #expect(made == 0)
        #expect(reduced == 0)
    }

    /// Whatever the redraw hands back, nothing larger than a thumbnail reaches the strip.
    @Test func aPageThatComesBackFullSizeIsAPlaceholder() throws {
        let pages = [try page(width: 2_400, height: 1_800)]
        let thumbnails = PageThumbnail.thumbnails(of: pages) { page, _ in page }
        #expect(thumbnails.count == 1)
        #expect(thumbnails.first?.image == nil)
    }
}
