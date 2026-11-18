//
//  TestValues.swift
//  ParsersTests
//
//  Created by Inez Amanda on 18/11/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import VaultCore

// Values written out in a test. A typo in one fails every run from the first, so these stop the run naming the
// value, where a `!` would only say it found nil. Unwrap what the code under test returns with `try #require`.
extension CalendarDate {
    static func day(_ year: Int, _ month: Int, _ day: Int) -> CalendarDate {
        guard let date = CalendarDate(year: year, month: month, day: day) else {
            preconditionFailure("Not a day: \(year)-\(month)-\(day)")
        }
        return date
    }
}
