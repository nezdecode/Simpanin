//
//  DocumentNumber.swift
//  Simpanin
//
//  Created by Inez Amanda on 28/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import Parsers

/// A NIK or SIM number as it's stored, shown, masked and copied.
nonisolated struct DocumentNumber: Equatable {
    let digits: String

    /// Every non-digit stored is dropped, exactly as Periksa data and the duplicate check strip it.
    init(_ stored: String) {
        digits = stored.filter(\.isASCIIDigit)
    }

    var isEmpty: Bool { digits.isEmpty }

    /// Groups of 4; an older SIM's 14 digits as 4-4-6 with dashes, as printed on the card.
    var shown: String { grouped(Array(digits)) }

    /// The first and last 4 digits, separators kept. Below 14 digits only the last 4, so enough stay hidden.
    var masked: String {
        let kept = digits.count >= 14 ? 4 : 0
        let hidden = kept..<max(kept, digits.count - 4)
        return grouped(digits.enumerated().map { hidden.contains($0.offset) ? "•" : $0.element })
    }

    var copied: String { digits }

    private func grouped(_ characters: [Character]) -> String {
        if characters.count == 14 {
            return [characters[0..<4], characters[4..<8], characters[8...]].map { String($0) }.joined(separator: "-")
        }
        return stride(from: 0, to: characters.count, by: 4)
            .map { String(characters[$0..<min($0 + 4, characters.count)]) }
            .joined(separator: " ")
    }
}
