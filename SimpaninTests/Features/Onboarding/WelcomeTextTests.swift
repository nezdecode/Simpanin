//
//  WelcomeTextTests.swift
//  SimpaninTests
//
//  Created by Inez Amanda on 3/11/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import Testing

@testable import Simpanin

@Suite("Welcome text")
struct WelcomeTextTests {
    @Test(arguments: [
        (UnlockMethod.faceID, "welcome.lock.faceID"),
        (.touchID, "welcome.lock.touchID"),
        (.passcode, "welcome.lock.passcode"),
        (.faceIDTurnedOff, "welcome.lock.passcode"),
        (.opticID, "welcome.lock.passcode"),
    ])
    func lockLineFollowsTheUnlockMethod(_ method: UnlockMethod, _ key: String) {
        #expect(WelcomeText.lockLine(for: method).key == key)
    }

    @Test func theTextsAreInTheCatalog() {
        let keys = [
            "welcome.title", "welcome.lock.faceID", "welcome.lock.touchID", "welcome.lock.passcode",
            "welcome.later", "privacy.noAccount", "privacy.deviceOnly",
        ]
        for key in keys {
            #expect(String(localized: String.LocalizationValue(key)) != key, "\(key) is missing")
        }
    }
}
