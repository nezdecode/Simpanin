//
//  SettingsUITests.swift
//  SimpaninUITests
//
//  Created by Inez Amanda on 18/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import XCTest

final class SettingsUITests: UITestCase {
    @MainActor
    func testSettingsAndOldVaults() throws {
        // A broken folder in Data lama, so Settings has a size to show next to it.
        let app = launch(["-SimpaninUITestBrokenOldVault"])
        app.buttons["list.settings"].tap()
        XCTAssertTrue(app.navigationBars["Pengaturan"].waitForExistence(timeout: 5))
        let oldVaults = app.buttons["settings.oldVaults"]
        XCTAssertTrue(oldVaults.waitForExistence(timeout: 5))
        XCTAssertTrue(oldVaults.label.contains("11"), "Data lama's size: \(oldVaults.label)")
        screenshot("04 settings")
        app.buttons["settings.oldVaults"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["oldVaults.unreadable"].waitForExistence(timeout: 5))
        screenshot("05 data lama")
    }

    /// Found in manual testing: Settings showed the old choice after going back and opening it again.
    @MainActor
    func testKunciOtomatisChoiceIsShownAgain() throws {
        let app = launch()
        app.buttons["list.settings"].tap()
        let row = app.buttons["settings.autoLock"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.label.contains("Setelah 1 menit"), row.label)
        row.tap()
        XCTAssertTrue(app.navigationBars["Kunci otomatis"].waitForExistence(timeout: 5))
        app.buttons["autoLock.fiveMinutes"].tap()
        XCTAssertTrue(app.buttons["autoLock.fiveMinutes"].isSelected)
        XCTAssertFalse(app.buttons["autoLock.oneMinute"].isSelected)
        screenshot("10 kunci otomatis")
        app.navigationBars["Kunci otomatis"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.label.contains("Setelah 5 menit"), row.label)

        app.navigationBars["Pengaturan"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["list.settings"].waitForExistence(timeout: 5))
        app.buttons["list.settings"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.label.contains("Setelah 5 menit"), "shown after reopening: \(row.label)")
    }
}
