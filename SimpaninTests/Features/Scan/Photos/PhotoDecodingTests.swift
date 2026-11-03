//
//  PhotoDecodingTests.swift
//  SimpaninTests
//
//  Created by Inez Amanda on 31/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import Simpanin

@Suite("Photo decoding")
struct PhotoDecodingTests {
    /// Whether the pixel near a corner is the red marker: top left, top right, bottom left or bottom right.
    func isRed(_ image: CGImage, top: Bool, left: Bool) throws -> Bool {
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: 4 * width * height)
        let context = try #require(
            CGContext(
                data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 4 * width,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        // The buffer's first row is the top of the image.
        let column = left ? 2 : width - 3
        let row = top ? 2 : height - 3
        let offset = 4 * (row * width + column)
        return pixels[offset] > 200 && pixels[offset + 1] < 60 && pixels[offset + 2] < 60
    }

    @Test func decodesJPEG() async throws {
        let page = try #require(
            await PhotoDecoding.shown(try SyntheticPhoto.file(try SyntheticPhoto.image(width: 400, height: 300))))
        #expect(page.width == 400)
        #expect(page.height == 300)
        #expect(try isRed(page, top: true, left: true))
    }

    /// Most iPhone photos are HEIC. Fails, rather than passing untested, where ImageIO has no HEIC encoder.
    @Test func decodesHEIC() async throws {
        let data = try SyntheticPhoto.file(
            try SyntheticPhoto.image(width: 400, height: 300), type: .heic, orientation: 6)
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        #expect(CGImageSourceGetType(source) as String? == UTType.heic.identifier)
        let page = try #require(await PhotoDecoding.shown(data))
        #expect(page.width == 300)
        #expect(page.height == 400)
        #expect(try isRed(page, top: true, left: false))
    }

    @Test func decodesPNG() async throws {
        let page = try #require(
            await PhotoDecoding.shown(
                try SyntheticPhoto.file(try SyntheticPhoto.image(width: 400, height: 300), type: .png)))
        #expect(page.width == 400)
        #expect(try isRed(page, top: true, left: true))
    }

    /// Orientation 6 is a phone held upright, its photo stored on its side: shown turned a quarter clockwise,
    /// so the stored top left lands top right. Orientation 8 turns the other way, to bottom left.
    @Test(arguments: [(6, true, false), (8, false, true)])
    func appliesOrientation(orientation: Int, top: Bool, left: Bool) async throws {
        let data = try SyntheticPhoto.file(try SyntheticPhoto.image(width: 400, height: 300), orientation: orientation)
        let page = try #require(await PhotoDecoding.shown(data))
        #expect(page.width == 300)
        #expect(page.height == 400)
        #expect(try isRed(page, top: top, left: left))
        #expect(try !isRed(page, top: true, left: true))
    }

    /// The file carries a small preview of its own; the page must come from the photo itself.
    @Test func shrinksToLongSide() async throws {
        let page = try #require(
            await PhotoDecoding.shown(try SyntheticPhoto.file(try SyntheticPhoto.image(width: 4_000, height: 500))))
        #expect(page.width == PageViewer.maxPixelSize)
        #expect(page.height == 375)
    }

    @Test func keepsSmallPhotoSize() async throws {
        let page = try #require(
            await PhotoDecoding.stored(try SyntheticPhoto.file(try SyntheticPhoto.image(width: 640, height: 480))))
        #expect(page.width == 640)
        #expect(page.height == 480)
    }

    @Test func storesAtStoredSize() async throws {
        let data = try SyntheticPhoto.file(try SyntheticPhoto.image(width: 6_500, height: 1_000))
        let stored = try #require(await PhotoDecoding.stored(data))
        #expect(stored.width == PhotoDecoding.storedPixelSize)
        let shown = try #require(await PhotoDecoding.shown(data))
        #expect(shown.width == PageViewer.maxPixelSize)
    }

    @Test func refusesUnreadableData() async {
        #expect(await PhotoDecoding.shown(Data("not a photo".utf8)) == nil)
        #expect(await PhotoDecoding.stored(Data()) == nil)
    }

    /// One photo that won't decode fails them all, so a document is never saved with a page missing.
    @Test func storedPagesFailWholeWhenOnePhotoFails() async throws {
        let good = try SyntheticPhoto.file(try SyntheticPhoto.image(width: 400, height: 300))
        #expect(await PhotoDecoding.storedPages([good, good])?.count == 2)
        #expect(await PhotoDecoding.storedPages([good, Data("not a photo".utf8)]) == nil)
    }

    /// A lock during Simpan cancels the save, so no more photos are decoded at the stored size.
    @Test func storedPagesStopWhenCancelled() async throws {
        let good = try SyntheticPhoto.file(try SyntheticPhoto.image(width: 400, height: 300))
        let saving = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await PhotoDecoding.storedPages([good, good])
        }
        #expect(await saving.value == nil)
    }

    /// What the vault gets from a photo with a place and a camera in it: none of that, and nothing that
    /// turns it, as it's already upright. ImageIO's own sizes in {Exif} are fine.
    @Test func savedPhotoPageHasNoMetadata() async throws {
        let data = try SyntheticPhoto.file(
            try SyntheticPhoto.image(width: 400, height: 300), orientation: 6, withMetadata: true)
        let original = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let originalProperties = try #require(
            CGImageSourceCopyPropertiesAtIndex(original, 0, nil) as? [CFString: Any])
        // The fixture really has what the page must not.
        try #require(originalProperties[kCGImagePropertyGPSDictionary] != nil)

        let page = try #require(await PhotoDecoding.stored(data))
        let saved = try #require(PageEncoding.jpeg(page))
        let source = try #require(CGImageSourceCreateWithData(saved as CFData, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        #expect(properties[kCGImagePropertyGPSDictionary] == nil)
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        #expect(tiff[kCGImagePropertyTIFFMake] == nil)
        #expect(tiff[kCGImagePropertyTIFFModel] == nil)
        #expect(tiff[kCGImagePropertyTIFFDateTime] == nil)
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        #expect(exif[kCGImagePropertyExifDateTimeOriginal] == nil)
        #expect((properties[kCGImagePropertyOrientation] as? Int ?? 1) == 1)
    }
}
