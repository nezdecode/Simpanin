//
//  UITestCase+Review.swift
//  SimpaninUITests
//
//  Created by Inez Amanda on 18/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import XCTest

/// Steps the scan tests share. A synthetic page and text stand in for the camera, which the simulator lacks.
extension UITestCase {
    /// "+" from the list, with the synthetic scan standing in for the camera.
    @MainActor
    func startScan(_ app: XCUIApplication) {
        XCTAssertTrue(app.navigationBars["Dokumen"].waitForExistence(timeout: 10))
        app.buttons["list.scan"].tap()
    }

    @MainActor
    func openReview(_ app: XCUIApplication) {
        startScan(app)
        XCTAssertTrue(app.textFields["review.field.name"].waitForExistence(timeout: 10))
    }

    @MainActor
    func replace(_ field: XCUIElement, with text: String) {
        field.tap()
        let old = field.value as? String ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count) + text)
    }
}
