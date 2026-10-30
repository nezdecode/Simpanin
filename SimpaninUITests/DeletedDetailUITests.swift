//
//  DeletedDetailUITests.swift
//  SimpaninUITests
//
//  Created by Inez Amanda on 30/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import XCTest

/// A document opened from Baru dihapus: read-only, with Pulihkan and Hapus permanen.
final class DeletedDetailUITests: UITestCase {
    /// Deletes the sample KTP and opens Baru dihapus from the list.
    @MainActor
    func deletedSample(_ arguments: [String] = []) -> XCUIApplication {
        let app = launch(arguments)
        addSamples(app, 1)
        tile(app, "Saya").press(forDuration: 1.2)
        app.buttons["Hapus"].tap()
        let bin = app.buttons["list.recentlyDeleted"]
        XCTAssertTrue(bin.waitForExistence(timeout: 5))
        bin.tap()
        XCTAssertTrue(rows(app).firstMatch.waitForExistence(timeout: 5))
        return app
    }

    /// The document must be the screen on top, back to Baru dihapus: a document pushed onto the stack's path
    /// once landed underneath it.
    @MainActor
    func openDeleted(_ app: XCUIApplication) {
        rows(app).firstMatch.tap()
        let bar = app.navigationBars["KTP"]
        XCTAssertTrue(bar.waitForExistence(timeout: 5))
        XCTAssertEqual(bar.buttons.element(boundBy: 0).label, "Baru dihapus")
        XCTAssertTrue(pages(app).waitForExistence(timeout: 5))
    }

    /// Pulihkan and Hapus permanen sit below the fields; the list builds them only once scrolled to.
    @MainActor
    func scrolledTo(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        let button = app.buttons[identifier]
        for _ in 0..<6 where !button.isHittable { app.swipeUp() }
        XCTAssertTrue(button.isHittable)
        return button
    }

    @MainActor
    func testOpenFromRecentlyDeleted() throws {
        let app = deletedSample()
        // VoiceOver reads the row as a button, and the footer says what a tap and a swipe do.
        XCTAssertTrue(app.buttons.matching(identifier: "document.row").firstMatch.exists)
        XCTAssertTrue(
            app.staticTexts["Ketuk untuk melihat dokumennya dulu. Geser atau tekan lama untuk langsung memulihkan."]
                .exists)
        openDeleted(app)
        XCTAssertTrue(app.navigationBars["KTP"].exists)
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Saya · dihapus '")).firstMatch.exists)
        XCTAssertEqual(
            app.staticTexts["detail.purgeNotice"].label,
            "Dihapus permanen dalam 30 hari. Pulihkan dulu untuk menyalin nomornya.")
        XCTAssertEqual(field(app, "nik").value as? String, "tersembunyi")
        XCTAssertFalse(app.buttons["detail.reveal"].exists)
        // A tap on the number does nothing either.
        field(app, "nik").tap()
        XCTAssertEqual(field(app, "nik").value as? String, "tersembunyi")
        XCTAssertFalse(app.buttons["detail.copy.nik"].exists)
        XCTAssertFalse(app.buttons["detail.copy.name"].exists)
        XCTAssertFalse(app.buttons["detail.delete"].exists)
        screenshot("59 deleted document")
        darkScreenshot("60 deleted document dark")
    }

    /// Settings → Baru dihapus is on the same stack, so its rows open the document too.
    @MainActor
    func testOpenFromSettingsRecentlyDeleted() throws {
        let app = deletedSample()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["list.settings"].tap()
        let bin = app.buttons["settings.recentlyDeleted"]
        XCTAssertTrue(bin.waitForExistence(timeout: 5))
        bin.tap()
        XCTAssertTrue(rows(app).firstMatch.waitForExistence(timeout: 5))
        openDeleted(app)
        _ = scrolledTo(app, "detail.restore")
    }

    @MainActor
    func testRestoreReturnsToRecentlyDeleted() throws {
        let app = deletedSample()
        openDeleted(app)
        scrolledTo(app, "detail.restore").tap()
        XCTAssertTrue(app.navigationBars["Baru dihapus"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Tidak ada dokumen yang baru dihapus"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(tile(app, "Saya").waitForExistence(timeout: 5))
    }

    /// Batal keeps it; Hapus permanen takes it out of Baru dihapus for good.
    @MainActor
    func testDeletePermanentlyAsksFirst() throws {
        let app = deletedSample()
        openDeleted(app)
        scrolledTo(app, "detail.deletePermanently").tap()
        let alert = app.alerts["Hapus permanen?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertTrue(alert.staticTexts["Dokumen ini dan kuncinya hilang, dan tidak bisa dipulihkan."].exists)
        screenshot("61 delete permanently asks")
        alert.buttons["Batal"].tap()
        XCTAssertTrue(app.buttons["detail.restore"].waitForExistence(timeout: 5))

        scrolledTo(app, "detail.deletePermanently").tap()
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["Hapus permanen"].tap()
        XCTAssertTrue(app.navigationBars["Baru dihapus"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Tidak ada dokumen yang baru dihapus"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["list.recentlyDeleted"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["list.recentlyDeleted"].label.contains("0"))
    }

    /// The list's save alert shows over the document after its own question has closed, and the document stays.
    @MainActor
    func testAFailedDeletePermanentlyShowsTheAlert() throws {
        let app = deletedSample(["-SimpaninUITestBinError"])
        openDeleted(app)
        scrolledTo(app, "detail.deletePermanently").tap()
        app.alerts["Hapus permanen?"].buttons["Hapus permanen"].tap()
        let alert = app.alerts["Perubahan belum tersimpan. Coba lagi."]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["detail.restore"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.navigationBars["KTP"].buttons.element(boundBy: 0).label, "Baru dihapus")
    }

    @MainActor
    func testAFailedRestoreShowsTheAlert() throws {
        let app = deletedSample(["-SimpaninUITestBinError"])
        openDeleted(app)
        scrolledTo(app, "detail.restore").tap()
        let alert = app.alerts["Perubahan belum tersimpan. Coba lagi."]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["detail.restore"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testLongPressRestores() throws {
        let app = deletedSample()
        rows(app).firstMatch.press(forDuration: 1.2)
        app.buttons["Pulihkan"].tap()
        XCTAssertTrue(app.staticTexts["Tidak ada dokumen yang baru dihapus"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testTheDeletedDocumentAtTheLargestTextSize() throws {
        let app = deletedSample(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        openDeleted(app)
        screenshot("62 deleted document at the largest text size")
        _ = scrolledTo(app, "detail.restore")
        screenshot("63 deleted document's buttons at the largest text size")
    }
}
