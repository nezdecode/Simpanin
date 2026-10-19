//
//  NIKTests.swift
//  ParsersTests
//
//  Created by Inez Amanda on 16/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Parsers
import Testing
import VaultCore

/// The one check the app uses after an edit: whether a NIK and a birth date agree.
@Suite("NIK and birth date")
struct NIKTests {
    let birth = CalendarDate(year: 1990, month: 8, day: 17)!

    @Test func aMatchingDateAgrees() {
        #expect(NIK.agrees("0012341708900001", withBirthDate: birth) == true)
    }

    /// Women have 40 added to the day.
    @Test func aWomansDayIsShiftedBy40() {
        #expect(NIK.agrees("0012345708900001", withBirthDate: birth) == true)
    }

    @Test func anotherDateDisagrees() {
        #expect(NIK.agrees("0012341808900001", withBirthDate: birth) == false)
        #expect(NIK.agrees("0012341708910001", withBirthDate: birth) == false)
    }

    /// A NIK too short to hold a date says nothing, so nothing is marked because of it.
    @Test func aNIKWithoutADateSaysNothing() {
        #expect(NIK.agrees("00123417", withBirthDate: birth) == nil)
        // An old SIM's number: 14 digits, no date.
        #expect(NIK.agrees("00000000000001", withBirthDate: birth) == nil)
    }
}
