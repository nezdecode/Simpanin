//
//  ReviewModel+Viewer.swift
//  Simpanin
//
//  Created by Inez Amanda on 30/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import CoreGraphics

/// What the page viewer shows over Periksa data.
extension ReviewModel {
    /// The strip's small copy, which stands in while the viewer's larger one is made.
    func thumbnail(_ index: Int) -> CGImage? {
        thumbnails.indices.contains(index) ? thumbnails[index] : nil
    }

    /// A page for the viewer, redrawn each time no larger than the viewer takes; the model doesn't keep it.
    func viewerPage(_ index: Int) async -> CGImage? {
        guard pages.indices.contains(index) else { return nil }
        return await Self.enlarged(pages[index])
    }

    /// Off the main actor: redrawing a full-size scan takes long enough to hold up a swipe.
    @concurrent private static func enlarged(_ page: CGImage) async -> CGImage? {
        reducedPage(page, longSide: PageViewer.maxPixelSize)
    }
}
