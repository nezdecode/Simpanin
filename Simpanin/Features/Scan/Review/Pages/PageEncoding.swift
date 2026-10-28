//
//  PageEncoding.swift
//  Simpanin
//
//  Created by Inez Amanda on 27/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Turns a page into the bytes that are sealed in the vault.
nonisolated enum PageEncoding {
    /// JPEG, like VisionKit's own pages, at a quality that keeps small print readable.
    static func jpeg(_ page: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, page, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}
