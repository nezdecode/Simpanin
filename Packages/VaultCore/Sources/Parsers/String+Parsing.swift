//
//  String+Parsing.swift
//  Parsers
//
//  Created by Inez Amanda on 15/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import VaultCore

extension String {
    /// The last dd-mm-yyyy in the text (a place usually comes first), with -, . or / between.
    var lastDate: CalendarDate? {
        guard let match = matches(of: /(\d{2})[-.\/](\d{2})[-.\/](\d{4})/).last,
            let day = Int(match.1), let month = Int(match.2), let year = Int(match.3)
        else { return nil }
        return CalendarDate(year: year, month: month, day: day)
    }

    /// Names are printed in capitals, so anything else (a digit, a small letter, a separator left from
    /// the label) is a misread.
    var looksLikeAName: Bool {
        guard let first, ("A"..."Z").contains(first) else { return false }
        return allSatisfy { ("A"..."Z").contains($0) || " .,'-".contains($0) }
    }
}

extension Character {
    var isASCIIDigit: Bool { ("0"..."9").contains(self) }
}
