//
//  ClassLetterSpikeTests.swift
//  SimpaninTests
//
//  Created by Inez Amanda on 28/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import CoreGraphics
import Testing

@testable import Simpanin

@Suite("Class letter spike")
struct ClassLetterSpikeTests {
    @Test func theCropSitsAboveTheNumberAndIsWider() throws {
        let rect = try #require(
            ClassLetterSpike.cropRect(aboveNumber: CGRect(x: 0.4, y: 0.5, width: 0.3, height: 0.05)))
        #expect(rect.minY.isApproximately(0.55))
        #expect(rect.height.isApproximately(0.2))
        #expect(rect.minX.isApproximately(0.35))
        #expect(rect.width.isApproximately(0.4))
    }

    @Test func theCropStopsAtThePageEdges() throws {
        let rect = try #require(
            ClassLetterSpike.cropRect(aboveNumber: CGRect(x: 0.02, y: 0.8, width: 0.96, height: 0.1)))
        #expect(rect.minX.isApproximately(0))
        #expect(rect.maxX.isApproximately(1))
        #expect(rect.maxY.isApproximately(1))
        #expect(rect.height.isApproximately(0.1))
    }

    @Test func aNumberAtTheTopLeavesNothingToRead() {
        #expect(ClassLetterSpike.cropRect(aboveNumber: CGRect(x: 0.2, y: 0.95, width: 0.5, height: 0.05)) == nil)
    }
}

extension CGFloat {
    fileprivate func isApproximately(_ other: CGFloat) -> Bool { abs(self - other) < 0.0001 }
}
