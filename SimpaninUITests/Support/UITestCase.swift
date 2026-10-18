//
//  UITestCase.swift
//  SimpaninUITests
//
//  Created by Inez Amanda on 18/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import XCTest

/// The main flows, on a fresh throwaway vault with an in-memory key, never a real vault.
/// Each screen is saved as a screenshot, for the design work.
/// Holds no tests: XCTest would run them again in every subclass.
class UITestCase: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func launch(_ arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-SimpaninUITest"] + arguments
        app.launch()
        return app
    }

    @MainActor
    func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func rows(_ app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: "document.row")
    }
}
