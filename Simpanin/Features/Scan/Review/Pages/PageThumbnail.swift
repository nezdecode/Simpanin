//
//  PageThumbnail.swift
//  Simpanin
//
//  Created by Inez Amanda on 30/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import CoreGraphics
import OSLog

/// A scanned page made small for the strip. Only `thumbnails(of:)` makes one, so a full-size scan can't be
/// handed to the strip by mistake.
nonisolated struct PageThumbnail: Sendable {
    /// This many pixels on the longer side: sharp at 112 pt, small in memory.
    static let pixelSize = 600

    /// Nil where it couldn't be made; the strip shows a grey tile with the page number.
    let image: CGImage?

    fileprivate init(image: CGImage?) {
        self.image = image
    }

    /// One per page, in order; none once the scan is cancelled, as by the lock, so its pages can go at once.
    static func thumbnails(
        of pages: [CGImage], reduce: (CGImage, Int) -> CGImage? = reducedPage
    ) -> [PageThumbnail] {
        var thumbnails: [PageThumbnail] = []
        for page in pages {
            guard !Task.isCancelled else { return [] }
            thumbnails.append(PageThumbnail(image: reduce(page, pixelSize)))
        }
        let missing = thumbnails.filter { $0.image == nil }.count
        if missing > 0 { Logger.scan.error("\(missing) of \(pages.count) thumbnails couldn't be made") }
        return thumbnails
    }

    /// Off the main actor: redrawing a few full-size pages takes long enough to freeze the screen.
    @concurrent static func made(of pages: [CGImage]) async -> [PageThumbnail] {
        thumbnails(of: pages)
    }
}
