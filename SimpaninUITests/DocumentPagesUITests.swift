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

    /// The page the viewer closes on is the one the document screen shows, and the one a tap opens again
    /// (found in manual testing on a device: the dots said 2 while page 1 showed).
    @MainActor
    func testThePageTheViewerClosesOnIsTheOneShown() throws {
        let app = launch()
        open(app, samples: 2, tile: "SIM A")
        let pager = pages(app)
        let close = app.buttons["viewer.close"]
        pager.tap()
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        for shown in [2, 3] { swipeViewer(app, left: true, to: shown) }
        close.tap()
        XCTAssertEqual(pager.value as? String, "3 dari 3")
        screenshot("52 back from the viewer on the last page")
        pager.tap()
        XCTAssertTrue(viewerShows(app, 3, of: 3))
        swipeViewer(app, left: false, to: 2)
        close.tap()
        XCTAssertEqual(pager.value as? String, "2 dari 3")
        screenshot("53 back from the viewer on a middle page")
        pager.tap()
        XCTAssertTrue(viewerShows(app, 2, of: 3))
    }

    /// Swiping the viewer away from a page and back to it before closing shows that page again.
    @MainActor
    func testGoingToAPageAndBackInTheViewerShowsTheFirst() throws {
        let app = launch()
        open(app, samples: 2, tile: "SIM A")
        let pager = pages(app)
        pager.tap()
        XCTAssertTrue(app.buttons["viewer.close"].waitForExistence(timeout: 5))
        swipeViewer(app, left: true, to: 2)
        swipeViewer(app, left: false, to: 1)
        app.buttons["viewer.close"].tap()
        XCTAssertEqual(pager.value as? String, "1 dari 3")
        screenshot("54 back on the first page after going to the second")
        pager.tap()
        XCTAssertTrue(viewerShows(app, 1, of: 3))
    }

    @MainActor
    private func swipeViewer(_ app: XCUIApplication, left: Bool, to page: Int) {
        if left { app.swipeLeft() } else { app.swipeRight() }
        XCTAssertTrue(viewerShows(app, page, of: 3))
        // The viewer hands its page back once a swipe has settled.
        RunLoop.current.run(until: Date().addingTimeInterval(1))
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
