//
//  ReadingOrderTests.swift
//  SimpaninTests
//
//  Created by Inez Amanda on 15/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import CoreGraphics
import Testing

@testable import Simpanin

@Suite("Reading order")
struct ReadingOrderTests {
    /// A piece starting at `left`, centred at `middle` from the bottom of the page, one line high.
    func piece(_ text: String, left: CGFloat, middle: CGFloat, height: CGFloat = 0.04) -> TextPiece {
        TextPiece(text: text, box: CGRect(x: left, y: middle - height / 2, width: 0.2, height: height))
    }

    @Test func topToBottom() {
        let pieces = [
            piece("Nama : BUDI", left: 0.1, middle: 0.7), piece("PROVINSI", left: 0.1, middle: 0.9),
            piece("NIK", left: 0.1, middle: 0.8),
        ]
        #expect(ReadingOrder.lines(pieces) == ["PROVINSI", "NIK", "Nama : BUDI"])
    }

    /// A label and its value on one row come back as two pieces, label first.
    @Test func leftToRightOnARow() {
        let pieces = [piece(": 0012341708900001", left: 0.4, middle: 0.8), piece("NIK", left: 0.1, middle: 0.8)]
        #expect(ReadingOrder.lines(pieces) == ["NIK", ": 0012341708900001"])
    }

    /// Pieces on one row are rarely at exactly the same height.
    @Test func aSlightlyUnevenRowIsStillOneRow() {
        let pieces = [
            piece(": BUDI CONTOH", left: 0.4, middle: 0.705), piece("Nama", left: 0.1, middle: 0.695),
            piece("NIK", left: 0.1, middle: 0.8),
        ]
        #expect(ReadingOrder.lines(pieces) == ["NIK", "Nama", ": BUDI CONTOH"])
    }

    @Test func nothingRecognized() {
        #expect(ReadingOrder.lines([]).isEmpty)
    }
}
