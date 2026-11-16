//
//  SetupUITests.swift
//  SimpaninUITests
//
//  Created by Inez Amanda on 16/11/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import XCTest

/// The screen a launch shows when the app couldn't be set up.
final class SetupUITests: UITestCase {
    @MainActor
    func testAFailedSetupOffersRetryAndRetryOpens() throws {
        // As many failures as the launch's own attempts (at init, inactive and active), so the screen shows.
        let app = launch(["-SimpaninUITestSetupFails", "3"])
        let retry = app.buttons["load.retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Simpanin tidak bisa disiapkan"].exists)
        screenshot("setup failed")
        retry.tap()
        XCTAssertTrue(app.navigationBars["Dokumen"].waitForExistence(timeout: 10))
    }

    /// A launch tries at init, then as the scene turns inactive and active. Only the inactive try comes before the
    /// failure screen would show, so with two failures the list shows and Coba lagi never does.
    @MainActor
    func testASetupThatFailsTwiceRecoversBeforeTheScreenShows() throws {
        let app = launch(["-SimpaninUITestSetupFails", "2"])
        XCTAssertTrue(app.navigationBars["Dokumen"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["load.retry"].exists)
    }

    @MainActor
    func testASetupThatFailsOnceRecoversOnItsOwn() throws {
        let app = launch(["-SimpaninUITestSetupFails", "1"])
        XCTAssertTrue(app.navigationBars["Dokumen"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["load.retry"].exists)
    }
}
