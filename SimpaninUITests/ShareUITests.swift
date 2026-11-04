//
//  ShareUITests.swift
//  SimpaninUITests
//
//  Created by Inez Amanda on 4/11/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import XCTest

/// Bagikan salinan: the purpose, the preview with the mark, and the share sheet.
final class ShareUITests: UITestCase {
    /// The document screen's Bagikan salinan, then the share screen with its preview.
    @MainActor
    func openShare(_ app: XCUIApplication, samples: Int = 1, tile text: String = "Saya") {
        open(app, samples: samples, tile: text)
        scrolledTo(app, "detail.share").tap()
        XCTAssertTrue(app.textFields["share.purpose"].waitForExistence(timeout: 5))
    }

    @MainActor
    func type(_ app: XCUIApplication, _ text: String) {
        let field = app.textFields["share.purpose"]
        field.tap()
        // Key by key, like a person; a long string can outrun the field.
        for character in text { field.typeText(String(character)) }
    }

    /// The share sheet's own list of targets, whatever its language.
    @MainActor
    func shareSheet(_ app: XCUIApplication) -> XCUIElement {
        app.otherElements["ActivityListView"]
    }

    @MainActor
    func testBagikanShowsOnlyOnALiveDocumentWithPages() throws {
        let app = launch()
        open(app, samples: 1, tile: "Saya")
        XCTAssertEqual(scrolledTo(app, "detail.share").label, "Bagikan salinan")
        screenshot("85 the document screen with Bagikan salinan")

        // From Baru dihapus it's read-only, so there's nothing to share.
        scrolledTo(app, "detail.delete").tap()
        let bin = app.buttons["list.recentlyDeleted"]
        XCTAssertTrue(bin.waitForExistence(timeout: 5))
        bin.tap()
        XCTAssertTrue(rows(app).firstMatch.waitForExistence(timeout: 5))
        rows(app).firstMatch.tap()
        XCTAssertTrue(scrolledTo(app, "detail.deletePermanently").exists)
        XCTAssertFalse(app.buttons["detail.share"].exists)
    }

    @MainActor
    func testBagikanIsDisabledWhileThePurposeIsEmpty() throws {
        let app = launch()
        openShare(app)
        let share = app.buttons["share.share"]
        XCTAssertFalse(share.isEnabled)
        type(app, "   ")
        XCTAssertFalse(share.isEnabled)
        type(app, "Sewa kos")
        XCTAssertTrue(share.isEnabled)
        screenshot("86 the share screen with a purpose")
    }

    @MainActor
    func testTheShareSheetOpensAndCancelReturnsToTheSheet() throws {
        let app = launch()
        openShare(app)
        type(app, "Sewa kos")
        app.buttons["share.share"].tap()
        XCTAssertTrue(shareSheet(app).waitForExistence(timeout: 15))
        screenshot("87 the share sheet")
        // Swiping it down is a cancel, like its close button, in any language.
        app.swipeDown(velocity: .fast)
        if shareSheet(app).exists { app.buttons["header.closeButton"].firstMatch.tap() }
        XCTAssertTrue(app.buttons["share.share"].waitForExistence(timeout: 5))
        XCTAssertFalse(shareSheet(app).exists)
        XCTAssertEqual(app.textFields["share.purpose"].value as? String, "Sewa kos")
    }

    @MainActor
    func testAPageThatFailsSaysSoAndSharesNothing() throws {
        let app = launch(["-SimpaninUITestLaterPagesFail"])
        openShare(app, samples: 2, tile: "SIM A")
        XCTAssertTrue(app.images["share.preview"].waitForExistence(timeout: 5))
        type(app, "Sewa kos")
        app.buttons["share.share"].tap()
        let problem = app.descendants(matching: .any)["share.problem"].firstMatch
        XCTAssertTrue(problem.waitForExistence(timeout: 15))
        XCTAssertTrue(problem.label.contains("tidak ada yang dibagikan"))
        XCTAssertFalse(shareSheet(app).exists)
        screenshot("88 a page that couldn't be opened")
    }

    @MainActor
    func testTheSheetAtTheLargestTextSizeKeepsBagikanReachable() throws {
        let app = launch(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        addSamples(app, 1)
        tile(app, "Saya").tap()
        scrolledTo(app, "detail.share").tap()
        let field = app.textFields["share.purpose"]
        for _ in 0..<6 where !field.isHittable { app.swipeUp() }
        type(app, "Sewa kos")
        XCTAssertTrue(app.buttons["share.share"].isHittable)
        XCTAssertTrue(app.buttons["share.share"].isEnabled)
        screenshot("89 the share screen at the largest text size")
    }

    @MainActor
    func testThePreviewAndFieldHaveTheirVoiceOverLabels() throws {
        let app = launch()
        openShare(app)
        let preview = app.images["share.preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        XCTAssertTrue(preview.label.hasPrefix("Pratinjau halaman 1 dengan tanda: "))
        XCTAssertEqual(app.textFields["share.purpose"].label, "Keperluan")
        type(app, "Sewa kos")
        let marked = NSPredicate(format: "label BEGINSWITH 'Pratinjau halaman 1 dengan tanda: Sewa kos · '")
        expectation(for: marked, evaluatedWith: preview)
        waitForExpectations(timeout: 5)
    }

    /// The lock closes the share sheet before its copies go, and says so after unlocking.
    @MainActor
    func testALockWithTheShareSheetUpClosesItAndSaysSo() throws {
        let app = launch()
        addSamples(app, 1)
        lockImmediately(app)
        tile(app, "Saya").tap()
        XCTAssertTrue(pages(app).waitForExistence(timeout: 5))
        scrolledTo(app, "detail.share").tap()
        type(app, "Sewa kos")
        app.buttons["share.share"].tap()
        XCTAssertTrue(shareSheet(app).waitForExistence(timeout: 15))
        XCUIDevice.shared.press(.home)
        // Coming back locks the vault; in UI tests the unlock prompt that follows succeeds by itself.
        app.activate()
        let notice = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'Berbagi dihentikan'"))
        XCTAssertTrue(notice.firstMatch.waitForExistence(timeout: 10))
        // The dismiss finishes a moment after the lock.
        XCTAssertTrue(shareSheet(app).waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.textFields["share.purpose"].exists)
        screenshot("90 a share stopped by the lock")
    }

    @MainActor
    func testAClosedSheetForgetsThePurpose() throws {
        let app = launch()
        openShare(app)
        type(app, "Sewa kos")
        app.buttons["share.cancel"].tap()
        scrolledTo(app, "detail.share").tap()
        let field = app.textFields["share.purpose"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertNotEqual(field.value as? String, "Sewa kos")
    }
}
