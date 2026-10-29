//
//  PagerLayout.swift
//  Simpanin
//
//  Created by Inez Amanda on 29/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import CoreGraphics

/// Where each page sits, so a swipe's end and a page chosen elsewhere land the same: a middle page centered
/// with `peek` of each neighbour showing, the first and last against their margins.
nonisolated struct PagerLayout: Equatable {
    static let peek: CGFloat = 18
    static let spacing: CGFloat = 8
    static let margin: CGFloat = 16

    let count: Int
    /// The scroll view's width.
    let width: CGFloat

    var pageWidth: CGFloat {
        max(0, count > 1 ? width - 2 * (Self.peek + Self.spacing) : width - 2 * Self.margin)
    }

    private var step: CGFloat { pageWidth + Self.spacing }
    private var contentWidth: CGFloat { 2 * Self.margin + CGFloat(count) * step - Self.spacing }

    /// The scroll offset that shows a page.
    func offset(for page: Int) -> CGFloat {
        let centered = Self.margin + CGFloat(page) * step + pageWidth / 2 - width / 2
        return min(max(centered, 0), max(contentWidth - width, 0))
    }

    /// Where a swipe that began at `start` ends: the page nearest where it would stop, one page away at most.
    func target(from start: CGFloat, proposed: CGFloat) -> CGFloat {
        let first = page(at: start)
        return offset(for: min(max(page(at: proposed), first - 1), first + 1))
    }

    /// The page nearest the middle of the screen at a scroll offset.
    func page(at offset: CGFloat) -> Int {
        guard count > 1, step > 0 else { return 0 }
        let middle = offset + width / 2
        return min(max(Int(((middle - Self.margin - pageWidth / 2) / step).rounded()), 0), count - 1)
    }
}
