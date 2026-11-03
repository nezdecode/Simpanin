//
//  SyntheticPhoto.swift
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

/// Photos made in code, standing in for ones picked from Photos. No real picture is ever used.
enum SyntheticPhoto {
    /// A grey photo with a red square in its top left corner, as stored, before any orientation.
    static func image(width: Int, height: Int) throws -> CGImage {
        let context = try #require(
            CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 4 * width,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let marker = max(1, min(width, height) / 4)
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        // A context's origin is at the bottom left.
        context.fill(CGRect(x: 0, y: height - marker, width: marker, height: marker))
        return try #require(context.makeImage())
    }

    /// The photo as a file, the way a camera writes one: an orientation, a small preview of its own, and the
    /// place and camera it was taken with.
    static func file(
        _ image: CGImage, type: UTType = .jpeg, orientation: Int = 1, withMetadata: Bool = false
    ) throws -> Data {
        let data = NSMutableData()
        let destination = try #require(
            CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil))
        var properties: [CFString: Any] = [
            kCGImagePropertyOrientation: orientation,
            kCGImageDestinationEmbedThumbnail: true,
        ]
        if withMetadata {
            properties[kCGImagePropertyGPSDictionary] = [
                kCGImagePropertyGPSLatitude: 1.5, kCGImagePropertyGPSLatitudeRef: "S",
                kCGImagePropertyGPSLongitude: 100.5, kCGImagePropertyGPSLongitudeRef: "E",
            ]
            properties[kCGImagePropertyTIFFDictionary] = [
                kCGImagePropertyTIFFMake: "Synthetic", kCGImagePropertyTIFFModel: "Test",
                kCGImagePropertyTIFFDateTime: "2026:01:01 10:00:00",
            ]
            properties[kCGImagePropertyExifDictionary] = [
                kCGImagePropertyExifDateTimeOriginal: "2026:01:01 10:00:00"
            ]
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        try #require(CGImageDestinationFinalize(destination))
        return data as Data
    }
}
