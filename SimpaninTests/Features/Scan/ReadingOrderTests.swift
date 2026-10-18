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

    /// Two pieces on one row come back left first.
    @Test func leftToRightOnARow() {
        let pieces = [piece("KOTA CONTOH", left: 0.4, middle: 0.8), piece("PROVINSI", left: 0.1, middle: 0.8)]
        #expect(ReadingOrder.lines(pieces) == ["PROVINSI", "KOTA CONTOH"])
    }

    /// Pieces on one row are rarely at exactly the same height.
    @Test func aSlightlyUnevenRowIsStillOneRow() {
        let pieces = [
            piece("BUDI CONTOH", left: 0.4, middle: 0.705), piece("Nama", left: 0.1, middle: 0.695),
            piece("NIK", left: 0.1, middle: 0.8),
        ]
        #expect(ReadingOrder.lines(pieces) == ["NIK", "Nama", "BUDI CONTOH"])
    }

    /// A KTP prints its values after a colon, and Vision returns the label and the value as two pieces.
    /// Joined, the parser reads "NIK : …" as one line instead of guessing the value from the next line.
    @Test func aValueAfterAColonJoinsItsLabel() {
        let pieces = [
            piece(": BUDI CONTOH", left: 0.4, middle: 0.7), piece("Nama", left: 0.1, middle: 0.7),
            piece(": 0012341708900001", left: 0.4, middle: 0.8), piece("NIK", left: 0.1, middle: 0.8),
        ]
        #expect(ReadingOrder.lines(pieces) == ["NIK : 0012341708900001", "Nama : BUDI CONTOH"])
    }

    /// Recognition reads a colon as a semicolon, as the parsers already allow.
    @Test func aValueAfterASemicolonJoinsItsLabel() {
        let pieces = [piece("; 0012341708900001", left: 0.4, middle: 0.8), piece("NIK", left: 0.1, middle: 0.8)]
        #expect(ReadingOrder.lines(pieces) == ["NIK ; 0012341708900001"])
    }

    /// A SIM has no colons: its number and its class on one row stay separate lines.
    @Test func piecesWithoutAColonStaySeparate() {
        let pieces = [piece("A", left: 0.8, middle: 0.8), piece("0012341708900001", left: 0.1, middle: 0.8)]
        #expect(ReadingOrder.lines(pieces) == ["0012341708900001", "A"])
    }

    /// A colon at the start of a row has no label to join.
    @Test func aColonPieceAloneOnItsRowStays() {
        let pieces = [piece("NIK", left: 0.1, middle: 0.8), piece(": 0012341708900001", left: 0.1, middle: 0.75)]
        #expect(ReadingOrder.lines(pieces) == ["NIK", ": 0012341708900001"])
    }

    @Test func nothingRecognized() {
        #expect(ReadingOrder.lines([]).isEmpty)
    }
}
