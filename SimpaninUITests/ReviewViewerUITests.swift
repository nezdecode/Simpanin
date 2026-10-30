//
//  ReviewViewerUITests.swift
//  SimpaninUITests
//
//  Created by Inez Amanda on 30/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import XCTest

/// A page of the scan enlarged from Periksa data. `-SimpaninUITestScanKTPAndSIM` reads a synthetic KTP on page 1
/// and a SIM A on page 2.
final class ReviewViewerUITests: UITestCase {
    @MainActor
    func testTappingAPageOpensTheViewerOnIt() throws {
        let app = launch(["-SimpaninUITestScanKTPAndSIM"])
        openReview(app)
        thumbnail(app, 2).tap()
        XCTAssertTrue(app.buttons["viewer.close"].waitForExistence(timeout: 5))
        XCTAssertTrue(viewerShows(app, 2, of: 2))
        screenshot("55 a page of the scan enlarged")
    }

    @MainActor
    func testTheViewerSwipesToTheOtherPage() throws {
        let app = launch(["-SimpaninUITestScanKTPAndSIM"])
        openReview(app)
        thumbnail(app, 1).tap()
        XCTAssertTrue(app.buttons["viewer.close"].waitForExistence(timeout: 5))
        app.swipeLeft()
        XCTAssertTrue(viewerShows(app, 2, of: 2))
        app.swipeRight()
        XCTAssertTrue(viewerShows(app, 1, of: 2))
    }

    /// Closing the viewer leaves the form as it was, a typed change too.
    @MainActor
    func testClosingTheViewerKeepsTheForm() throws {
        let app = launch(["-SimpaninUITestScanKTPAndSIM"])
        openReview(app)
        let name = app.textFields["review.field.name"]
        replace(name, with: "ANI CONTOH")
        app.navigationBars.buttons["review.done"].tap()
        thumbnail(app, 1).tap()
        let close = app.buttons["viewer.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        close.tap()
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual(name.value as? String, "ANI CONTOH")
        XCTAssertTrue(app.navigationBars["Periksa data"].exists)
    }

    /// The keyboard closes, so it isn't back over the form when the viewer closes.
    @MainActor
    func testTappingAPageClosesTheKeyboard() throws {
        let app = launch(["-SimpaninUITestScanKTPAndSIM"])
        openReview(app)
        app.textFields["review.field.name"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        thumbnail(app, 1).tap()
        let close = app.buttons["viewer.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        close.tap()
        XCTAssertTrue(app.textFields["review.field.name"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.keyboards.firstMatch.exists)
    }

    /// Its hint can't be read by a UI test; VoiceOver on a device checks it.
    @MainActor
    func testAThumbnailIsAButton() throws {
        let app = launch(["-SimpaninUITestScanKTPAndSIM"])
        openReview(app)
        let page = app.buttons["review.page.2"]
        XCTAssertTrue(page.exists)
        XCTAssertEqual(page.label, "Halaman 2 dari 2, terbaca sebagai SIM A")
        XCTAssertTrue(page.isEnabled)
    }

    @MainActor
    func testThePageHasNoMenu() throws {
        let app = launch(["-SimpaninUITestScan"])
        openReview(app)
        thumbnail(app, 1).tap()
        XCTAssertTrue(app.buttons["viewer.close"].waitForExistence(timeout: 5))
        app.press(forDuration: 1.5)
        XCTAssertFalse(app.buttons["Salin"].exists)
        XCTAssertFalse(app.buttons["Bagikan"].exists)
        XCTAssertFalse(app.buttons["Copy"].exists)
    }

    @MainActor
    func testTheLockWithTheViewerOpenDropsTheScan() throws {
        let app = launch(["-SimpaninUITestScan"])
        lockImmediately(app)
        openReview(app)
        thumbnail(app, 1).tap()
        XCTAssertTrue(app.buttons["viewer.close"].waitForExistence(timeout: 5))
        XCUIDevice.shared.press(.home)
        // Coming back locks the vault; in UI tests the unlock prompt that follows succeeds by itself.
        app.activate()
        let notice = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'Pindaian yang belum disimpan'"))
        XCTAssertTrue(notice.firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["viewer.close"].exists)
        XCTAssertFalse(app.textFields["review.field.name"].exists)
    }

    /// The pages shown while a rescan is read are about to be replaced, so they look dimmed and don't open.
    @MainActor
    func testThePagesCantBeOpenedWhileARescanIsRead() throws {
        let app = launch(["-SimpaninUITestScan", "-SimpaninUITestSlowRead"])
        openReview(app)
        let page = app.buttons["review.page.1"]
        XCTAssertTrue(page.isEnabled)
        app.navigationBars.buttons["review.rescan"].tap()
        expectation(for: NSPredicate(format: "isEnabled == false"), evaluatedWith: page)
        waitForExpectations(timeout: 2)
        screenshot("56 pages dimmed while a rescan is read")
        // Not tapped: a tap waits for the app to be idle, which the reading spinner keeps it from until the
        // read is over and the page is enabled again. A disabled button is what VoiceOver reads as unavailable.
        expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: page)
        waitForExpectations(timeout: 10)
    }

    @MainActor
    private func thumbnail(_ app: XCUIApplication, _ number: Int) -> XCUIElement {
        app.buttons["review.page.\(number)"]
    }
}
