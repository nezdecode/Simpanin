//
//  UITestCase+DocumentDetail.swift
//  SimpaninUITests
//
//  Created by Inez Amanda on 29/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import XCTest

/// The DEBUG samples, in turn: a KTP "Saya", a SIM A with three pages, a passport, an older SIM C "Ibu" and a KTP
/// without a NIK. Their numbers start with 00.
extension UITestCase {
    @MainActor
    func addSamples(_ app: XCUIApplication, _ count: Int) {
        XCTAssertTrue(app.buttons["list.addSample"].waitForExistence(timeout: 10))
        for _ in 0..<count { app.buttons["list.addSample"].tap() }
        XCTAssertTrue(rows(app).element(boundBy: count - 1).waitForExistence(timeout: 5))
    }

    @MainActor
    func open(_ app: XCUIApplication, samples: Int, tile text: String) {
        if samples > 0 { addSamples(app, samples) }
        tile(app, text).tap()
        // The top of the screen: at the largest text size the rows further down aren't built until scrolled to.
        XCTAssertTrue(pages(app).waitForExistence(timeout: 5))
    }

    @MainActor
    func tile(_ app: XCUIApplication, _ text: String, without other: String? = nil) -> XCUIElement {
        let format = other == nil ? "label CONTAINS %@" : "label CONTAINS %@ AND NOT (label CONTAINS %@)"
        return rows(app).matching(NSPredicate(format: format, argumentArray: [text, other ?? ""])).firstMatch
    }

    /// The pager is one element, for VoiceOver.
    @MainActor
    func pages(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["detail.pages"]
    }

    @MainActor
    func field(_ app: XCUIApplication, _ key: String) -> XCUIElement {
        app.descendants(matching: .any)["detail.field.\(key)"]
    }

    @MainActor
    func lockImmediately(_ app: XCUIApplication) {
        app.buttons["list.settings"].tap()
        let row = app.buttons["settings.autoLock"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        app.buttons["autoLock.immediately"].tap()
        app.navigationBars["Kunci otomatis"].buttons.element(boundBy: 0).tap()
        app.navigationBars["Pengaturan"].buttons.element(boundBy: 0).tap()
    }
}
