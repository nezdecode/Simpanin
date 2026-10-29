//
//  PageReductionTests.swift
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

@Suite("Page reduction")
struct PageReductionTests {
    /// A page of one colour, so a reduced copy can be checked for still showing it.
    func page(width: Int, height: Int) throws -> CGImage {
        let context = try #require(
            CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 4 * width,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try #require(context.makeImage())
    }

    /// The red of the middle pixel, from 0 to 255.
    func middleRed(of image: CGImage) throws -> UInt8 {
        var pixel: [UInt8] = [0, 0, 0, 0]
        let context = try #require(
            CGContext(
                data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return pixel[0]
    }

    @Test func reducesToTheLongSide() throws {
        let reduced = try #require(reducedPage(try page(width: 2_400, height: 1_800), longSide: 600))
        #expect(reduced.width == 600)
        #expect(reduced.height == 450)
        #expect(try middleRed(of: reduced) == 255)
    }

    @Test func aSmallPageKeepsItsSize() throws {
        let reduced = try #require(reducedPage(try page(width: 300, height: 200), longSide: 600))
        #expect(reduced.width == 300)
        #expect(reduced.height == 200)
    }

    @Test func keepsTheAspectRatio() throws {
        let reduced = try #require(reducedPage(try page(width: 3_000, height: 1_000), longSide: 600))
        #expect(reduced.width == 600)
        #expect(reduced.height == 200)
    }

    @Test func aPortraitPageUsesItsHeight() throws {
        let reduced = try #require(reducedPage(try page(width: 1_000, height: 2_000), longSide: 600))
        #expect(reduced.width == 300)
        #expect(reduced.height == 600)
    }

    /// The strip's size is a memory rule too, so it's pinned here rather than read from the constant.
    @Test func thumbnailsAreAtMost600PixelsLong() async throws {
        let pages = [try page(width: 2_400, height: 1_800), try page(width: 900, height: 1_800)]
        let thumbnails = await PageStrip.thumbnails(of: pages)
        #expect(thumbnails.count == 2)
        #expect(thumbnails.map { $0.map { max($0.width, $0.height) } } == [600, 600])
    }
}
