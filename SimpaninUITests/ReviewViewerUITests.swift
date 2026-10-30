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

    /// As on the document screen: the zoom back to the thumbnail lets a swipe down close it.
    @MainActor
    func testASwipeDownClosesTheViewer() throws {
        let app = launch(["-SimpaninUITestScanKTPAndSIM"])
        openReview(app)
        thumbnail(app, 2).tap()
        let close = app.buttons["viewer.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        app.swipeDown(velocity: .fast)
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: close)
        waitForExpectations(timeout: 5)
        XCTAssertTrue(app.navigationBars["Periksa data"].exists)
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
        // The first read is slow too, so this waits longer than openReview does.
        XCTAssertTrue(app.navigationBars["Dokumen"].waitForExistence(timeout: 10))
        app.buttons["list.scan"].tap()
        XCTAssertTrue(app.textFields["review.field.name"].waitForExistence(timeout: 20))
        let page = app.buttons["review.page.1"]
        XCTAssertTrue(page.isEnabled)
        app.navigationBars.buttons["review.rescan"].tap()
        expectation(for: NSPredicate(format: "isEnabled == false"), evaluatedWith: page)
        waitForExpectations(timeout: 2)
        screenshot("56 pages dimmed while a rescan is read")
        page.tap()
        XCTAssertFalse(app.buttons["viewer.close"].waitForExistence(timeout: 1))
        expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: page)
        waitForExpectations(timeout: 15)
    }

    /// The synthetic KTP's name is marked: the bar shows the NIK as printed, and the name.
    @MainActor
    func testTheViewerShowsTheFieldBeingChecked() throws {
        let app = launch(["-SimpaninUITestScan"])
        openReview(app)
        thumbnail(app, 1).tap()
        let bar = app.descendants(matching: .any)["viewer.checkedFields"]
        XCTAssertTrue(bar.waitForExistence(timeout: 5))
        let nik = app.descendants(matching: .any)["viewer.checkedField.nik"]
        XCTAssertTrue(nik.label.contains("NIK"))
        XCTAssertTrue(nik.label.contains("0012341708900001"))
        XCTAssertTrue(app.descendants(matching: .any)["viewer.checkedField.name"].label.contains("BUDI C0NTOH"))
        XCTAssertFalse(app.descendants(matching: .any)["viewer.checkedField.birthDate"].exists)
        screenshot("57 the field being checked under the page")
    }

    /// What Simpan would save is what's compared, after a correction too; a corrected name isn't marked any more.
    @MainActor
    func testTheBarShowsACorrectedValue() throws {
        let app = launch(["-SimpaninUITestScan"])
        openReview(app)
        replace(app.textFields["review.field.nik"], with: "0012341708900002")
        replace(app.textFields["review.field.name"], with: "BUDI CONTOH")
        app.navigationBars.buttons["review.done"].tap()
        thumbnail(app, 1).tap()
        let nik = app.descendants(matching: .any)["viewer.checkedField.nik"]
        XCTAssertTrue(nik.waitForExistence(timeout: 5))
        XCTAssertTrue(nik.label.contains("0012341708900002"))
        XCTAssertFalse(app.descendants(matching: .any)["viewer.checkedField.name"].exists)
    }

    @MainActor
    func testTheBarHasNoMenu() throws {
        let app = launch(["-SimpaninUITestScan"])
        openReview(app)
        thumbnail(app, 1).tap()
        let nik = app.descendants(matching: .any)["viewer.checkedField.nik"]
        XCTAssertTrue(nik.waitForExistence(timeout: 5))
        nik.press(forDuration: 1.5)
        XCTAssertFalse(app.buttons["Salin"].exists)
        XCTAssertFalse(app.buttons["Copy"].exists)
        XCTAssertFalse(app.menuItems.firstMatch.exists)
    }

    /// The bar grows to a cap and scrolls past it, so the page keeps its room.
    @MainActor
    func testTheViewerAtTheLargestTextSize() throws {
        let app = launch([
            "-SimpaninUITestScan", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
        ])
        XCTAssertTrue(app.navigationBars["Dokumen"].waitForExistence(timeout: 10))
        app.buttons["list.scan"].tap()
        // The top of the form: at this size the lower rows aren't built until scrolled to.
        let page = thumbnail(app, 1)
        XCTAssertTrue(page.waitForExistence(timeout: 10))
        page.tap()
        let bar = app.descendants(matching: .any)["viewer.checkedFields"]
        XCTAssertTrue(bar.waitForExistence(timeout: 5))
        XCTAssertLessThan(bar.frame.height, app.frame.height / 2)
        screenshot("58 the field bar at the largest text size")
    }

    @MainActor
    private func thumbnail(_ app: XCUIApplication, _ number: Int) -> XCUIElement {
        app.buttons["review.page.\(number)"]
    }
}
