//
//  DocumentPagesUITests.swift
//  SimpaninUITests
//
//  Created by Inez Amanda on 29/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import XCTest

/// The document screen's pages and the viewer that enlarges them.
final class DocumentPagesUITests: UITestCase {
    /// One page per swipe, the last one too, and the viewer opens and closes on the page shown.
    @MainActor
    func testPagesSwipeOneByOne() throws {
        let app = launch()
        open(app, samples: 2, tile: "SIM A")
        let pager = pages(app)
        XCTAssertEqual(pager.label, "Halaman")
        XCTAssertEqual(pager.value as? String, "1 dari 3")
        screenshot("50 the next page peeking in")
        for shown in ["2 dari 3", "3 dari 3"] {
            pager.swipeLeft()
            expectation(for: NSPredicate(format: "value == %@", shown), evaluatedWith: pager)
            waitForExpectations(timeout: 5)
        }
        screenshot("51 the last page")
        pager.tap()
        let close = app.buttons["viewer.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        close.tap()
        XCTAssertTrue(pager.waitForExistence(timeout: 5))
        XCTAssertEqual(pager.value as? String, "3 dari 3")

        // The viewer keeps its own page while open and hands it back when it closes.
        pager.tap()
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        app.swipeRight()
        let viewerOnTwo = NSPredicate(format: "label == 'Halaman 2 dari 3'")
        expectation(
            for: NSPredicate(format: "count > 0"), evaluatedWith: app.descendants(matching: .any).matching(viewerOnTwo))
        waitForExpectations(timeout: 5)
        close.tap()
        expectation(for: NSPredicate(format: "value == '2 dari 3'"), evaluatedWith: pager)
        waitForExpectations(timeout: 5)
    }

    /// Opening the viewer masks the number again.
    @MainActor
    func testEnlargePageAndClose() throws {
        let app = launch()
        open(app, samples: 1, tile: "Saya")
        app.buttons["detail.reveal"].tap()
        let page = pages(app)
        XCTAssertTrue(page.waitForExistence(timeout: 5))
        page.tap()
        let close = app.buttons["viewer.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        XCTAssertEqual(close.label, "Tutup")
        screenshot("44 page enlarged")
        close.tap()
        XCTAssertTrue(page.waitForExistence(timeout: 5))
        XCTAssertFalse(close.exists)
        XCTAssertEqual(field(app, "nik").value as? String, "tersembunyi")
    }

    @MainActor
    func testPageHasNoContextMenu() throws {
        let app = launch()
        open(app, samples: 1, tile: "Saya")
        let page = pages(app)
        XCTAssertTrue(page.waitForExistence(timeout: 5))
        page.press(forDuration: 1.5)
        XCTAssertFalse(app.buttons["Salin"].exists)
        XCTAssertFalse(app.buttons["Bagikan"].exists)
        XCTAssertFalse(app.buttons["Copy"].exists)
    }

    @MainActor
    func testLockWhileThePageViewerIsOpenReturnsToTheList() throws {
        let app = launch()
        lockImmediately(app)
        open(app, samples: 1, tile: "Saya")
        pages(app).tap()
        XCTAssertTrue(app.buttons["viewer.close"].waitForExistence(timeout: 5))
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(rows(app).firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["viewer.close"].exists)
        XCTAssertFalse(field(app, "nik").exists)
    }
}
