//
//  PhotoDecoding.swift
//  Simpanin
//
//  Created by Inez Amanda on 31/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import CoreGraphics
import Foundation

/// A photo picked from Photos, decoded upright from its file. Never the file's own small preview, and no
/// metadata survives: a decoded page is only pixels, so its GPS, camera and dates stay behind.
nonisolated enum PhotoDecoding {
    /// Saved pages keep this many pixels on their longer side: 12 and 24 MP photos whole, a 48 MP one shrunk.
    static let storedPixelSize = 6_000

    /// For showing and reading the text, at the viewer's size.
    static func shown(_ data: Data) async -> CGImage? {
        await CGImage.reduced(from: data, to: PageViewer.maxPixelSize)
    }

    /// For the vault, decoded at Simpan.
    static func stored(_ data: Data) async -> CGImage? {
        await CGImage.reduced(from: data, to: storedPixelSize)
    }
}
