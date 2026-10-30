//
//  ReviewModelTests+Viewer.swift
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

/// What the page viewer shows over Periksa data.
extension ReviewModelTests {
    /// The viewer never gets a full-size scan, here as on the document screen.
    @Test func theViewerGetsAPageAtMost3000PixelsLong() async throws {
        let review = model()
        review.loadScan(Self.ktp, pages: [try page(width: 4_000)])
        let shown = try #require(await review.viewerPage(0))
        #expect(shown.width == PageViewer.maxPixelSize)
        #expect(PageViewer.maxPixelSize == 3_000)
    }

    @Test func aPageThatIsntThereGivesTheViewerNothing() async throws {
        let review = model()
        review.loadScan(Self.ktp, pages: [try page()])
        #expect(await review.viewerPage(1) == nil)
        #expect(await review.viewerPage(-1) == nil)
    }
}
