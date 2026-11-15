//
//  AppDelegateTests.swift
//  SimpaninTests
//
//  Created by Inez Amanda on 16/11/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Testing
import UIKit

@testable import Simpanin

@MainActor
@Suite("App delegate")
struct AppDelegateTests {
    /// Asked through the running app's delegate, so the test also fails if the adaptor isn't wired.
    private func allows(_ identifier: UIApplication.ExtensionPointIdentifier) -> Bool? {
        UIApplication.shared.delegate?.application?(.shared, shouldAllowExtensionPointIdentifier: identifier)
    }

    @Test func thirdPartyKeyboardsAreRefused() {
        #expect(allows(.keyboard) == false)
    }

    @Test func otherExtensionPointsAreAllowed() {
        #expect(allows(UIApplication.ExtensionPointIdentifier(rawValue: "com.example.other")) != false)
    }
}
