//
//  ReadingOrder.swift
//  Simpanin
//
//  Created by Inez Amanda on 15/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import CoreGraphics

/// A piece of recognised text and where it sits on the page, in Vision's normalized coordinates:
/// 0 to 1, with the origin at the bottom left.
nonisolated struct TextPiece: Equatable, Sendable {
    var text: String
    var box: CGRect
}

/// Puts recognised pieces in reading order, top to bottom and left to right, as the parsers expect.
/// Pieces on one row stay separate lines, so a SIM's class isn't glued onto its number, except a value
/// after a colon, which joins its label.
nonisolated enum ReadingOrder {
    static func lines(_ pieces: [TextPiece]) -> [String] {
        var rows: [[TextPiece]] = []
        for piece in pieces.sorted(by: { $0.box.midY > $1.box.midY }) {
            // Pieces on one row are rarely at exactly the same height, so half a line of slack.
            if let last = rows.last?.first,
                abs(last.box.midY - piece.box.midY) < min(last.box.height, piece.box.height) / 2
            {
                rows[rows.count - 1].append(piece)
            } else {
                rows.append([piece])
            }
        }
        return rows.flatMap { row in
            var lines: [String] = []
            for piece in row.sorted(by: { $0.box.minX < $1.box.minX }) {
                // A KTP prints its values after a colon, and Vision returns label and value as two pieces.
                if piece.text.hasPrefix(":"), let label = lines.popLast() {
                    lines.append(label + " " + piece.text)
                } else {
                    lines.append(piece.text)
                }
            }
            return lines
        }
    }
}
