//
//  PagerLayoutTests.swift
//  SimpaninTests
//
//  Created by Inez Amanda on 29/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import CoreGraphics
import Testing

@testable import Simpanin

/// The pager on an iPhone 17, 402 pt wide.
@Suite("Pager layout")
struct PagerLayoutTests {
    let three = PagerLayout(count: 3, width: 402)

    func left(_ layout: PagerLayout, page: Int) -> CGFloat {
        PagerLayout.margin + CGFloat(page) * (layout.pageWidth + PagerLayout.spacing) - layout.offset(for: page)
    }

    @Test func aMiddlePageIsCentered() {
        let pageLeft = left(three, page: 1)
        #expect(pageLeft == 402 - (pageLeft + three.pageWidth))
        #expect(pageLeft - PagerLayout.spacing == PagerLayout.peek)
    }

    @Test func theFirstPageKeepsItsLeftMargin() {
        #expect(three.offset(for: 0) == 0)
    }

    @Test func theLastPageKeepsItsRightMargin() {
        #expect(left(three, page: 2) + three.pageWidth == 402 - PagerLayout.margin)
    }

    @Test func onePageHasTheScreensMargins() {
        let one = PagerLayout(count: 1, width: 402)
        #expect(one.pageWidth == 402 - 2 * PagerLayout.margin)
        #expect(one.offset(for: 0) == 0)
    }

    @Test func theNearestPageToAnOffsetIsFound() {
        #expect(three.page(at: three.offset(for: 1)) == 1)
        #expect(three.page(at: three.offset(for: 1) + 100) == 1)
        #expect(three.page(at: three.offset(for: 1) + 250) == 2)
        #expect(three.page(at: -50) == 0)
        #expect(three.page(at: 10_000) == 2)
    }
}
