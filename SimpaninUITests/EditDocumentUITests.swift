//
//  EditDocumentUITests.swift
//  SimpaninUITests
//
//  Created by Inez Amanda on 7/11/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import XCTest

/// Edit dokumen, opened from the document screen, on the DEBUG samples. Their numbers start with 00.
final class EditDocumentUITests: UITestCase {
    @MainActor
    func openEdit(_ app: XCUIApplication) {
        let edit = app.navigationBars.buttons["detail.edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.tap()
        XCTAssertTrue(app.navigationBars["Edit dokumen"].waitForExistence(timeout: 5))
    }

    /// Key by key, like a person: one long typeText can outrun a field that rewrites itself.
    @MainActor
    func type(_ text: String, into field: XCUIElement) {
        replace(field, with: "")
        for character in text { field.typeText(String(character)) }
    }

    @MainActor
    func sheetCloses(_ app: XCUIApplication) -> Bool {
        let gone = expectation(
            for: NSPredicate(format: "exists == false"), evaluatedWith: app.navigationBars["Edit dokumen"])
        return XCTWaiter.wait(for: [gone], timeout: 5) == .completed
    }

    /// The KTP saved without a NIK gets one, and the document screen shows it masked.
    @MainActor
    func testFixingANIKShowsOnTheDocumentScreen() throws {
        let app = launch()
        addSamples(app, 5)
        tile(app, "KTP", without: "Saya").tap()
        XCTAssertTrue(pages(app).waitForExistence(timeout: 5))
        openEdit(app)
        XCTAssertFalse(app.buttons["review.save"].isEnabled)
        screenshot("91 edit KTP")
        darkScreenshot("94 edit KTP dark")
        type("0012341708900005", into: app.textFields["review.field.nik"])
        app.navigationBars.buttons["edit.done"].tap()
        app.buttons["review.save"].tap()
        XCTAssertTrue(sheetCloses(app))
        XCTAssertTrue(app.staticTexts["Perubahan disimpan"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["0012 •••• •••• 0005"].waitForExistence(timeout: 5))
    }

    /// The pages are there to check a value against, and open in the viewer from the sheet.
    @MainActor
    func testPagesShowAndEnlarge() throws {
        let app = launch()
        addSamples(app, 2)
        tile(app, "SIM A").tap()
        XCTAssertTrue(pages(app).waitForExistence(timeout: 5))
        openEdit(app)
        // The document screen's pages are still there under the sheet; the sheet's are the ones in reach.
        let all = app.descendants(matching: .any).matching(identifier: "detail.pages")
        XCTAssertTrue(all.element(boundBy: 1).waitForExistence(timeout: 5))
        let sheetPages = try XCTUnwrap(all.allElementsBoundByIndex.last { $0.isHittable })
        sheetPages.tap()
        XCTAssertTrue(viewerShows(app, 1, of: 3))
    }

    @MainActor
    func testCancelWithoutChangesCloses() throws {
        let app = launch()
        open(app, samples: 1, tile: "Saya")
        openEdit(app)
        app.navigationBars.buttons["edit.cancel"].tap()
        XCTAssertTrue(sheetCloses(app))
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }

    /// Batal after a change asks first: Lanjut edit keeps the change, Buang drops it.
    @MainActor
    func testCancelWithChangesAsks() throws {
        let app = launch()
        open(app, samples: 1, tile: "Saya")
        openEdit(app)
        replace(app.textFields["review.label"], with: "Kantor")
        app.navigationBars.buttons["edit.done"].tap()
        app.navigationBars.buttons["edit.cancel"].tap()
        let alert = app.alerts["Buang perubahan?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        screenshot("92 edit discard")
        alert.buttons["Lanjut edit"].tap()
        XCTAssertEqual(app.textFields["review.label"].value as? String, "Kantor")
        app.navigationBars.buttons["edit.cancel"].tap()
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["Buang"].tap()
        XCTAssertTrue(sheetCloses(app))
        let added = NSPredicate(format: "label BEGINSWITH 'Saya · ditambahkan '")
        XCTAssertTrue(app.staticTexts.matching(added).firstMatch.exists)
    }

    /// A NIK of the wrong length is refused, and Simpan goes back to it, as in Periksa data.
    @MainActor
    func testAWrongNIKIsRefusedAndFocused() throws {
        let app = launch()
        open(app, samples: 1, tile: "Saya")
        openEdit(app)
        let nik = app.textFields["review.field.nik"]
        replace(nik, with: "00123")
        app.navigationBars.buttons["edit.done"].tap()
        XCTAssertTrue(app.staticTexts["NIK harus 16 angka."].waitForExistence(timeout: 5))
        app.buttons["review.save"].tap()
        expectation(for: NSPredicate(format: "hasKeyboardFocus == true"), evaluatedWith: nik)
        waitForExpectations(timeout: 5)
        XCTAssertEqual(nik.label, "NIK, perlu diperbaiki: NIK harus 16 angka.")
        XCTAssertTrue(app.navigationBars["Edit dokumen"].exists)
    }

    /// The fifth sample is a KTP with no NIK; given the first one's, Simpan warns, and Kembali keeps the sheet.
    @MainActor
    func testAChangedNumberMatchingAnotherWarns() throws {
        let app = launch()
        addSamples(app, 5)
        tile(app, "KTP", without: "Saya").tap()
        XCTAssertTrue(pages(app).waitForExistence(timeout: 5))
        openEdit(app)
        type("0000000000000001", into: app.textFields["review.field.nik"])
        app.navigationBars.buttons["edit.done"].tap()
        app.buttons["review.save"].tap()
        let alert = app.alerts["Kamu sudah punya KTP dengan NIK ini."]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["Kembali"].tap()
        XCTAssertTrue(app.navigationBars["Edit dokumen"].exists)
    }

    /// A new label shows on the screen and on the list's tile.
    @MainActor
    func testTheTileShowsTheEditedLabel() throws {
        let app = launch()
        open(app, samples: 1, tile: "Saya")
        openEdit(app)
        replace(app.textFields["review.label"], with: "Kantor")
        app.navigationBars.buttons["edit.done"].tap()
        app.buttons["review.save"].tap()
        XCTAssertTrue(sheetCloses(app))
        let added = NSPredicate(format: "label BEGINSWITH 'Kantor · ditambahkan '")
        XCTAssertTrue(app.staticTexts.matching(added).firstMatch.waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(tile(app, "Kantor").waitForExistence(timeout: 5))
    }

    /// A failed save says so and keeps the sheet open with the change.
    @MainActor
    func testAFailedSaveKeepsTheEdits() throws {
        let app = launch(["-SimpaninUITestEditError"])
        open(app, samples: 1, tile: "Saya")
        openEdit(app)
        replace(app.textFields["review.label"], with: "Kantor")
        app.navigationBars.buttons["edit.done"].tap()
        app.buttons["review.save"].tap()
        let alert = app.alerts["Perubahan belum tersimpan. Coba lagi."]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Edit dokumen"].exists)
        XCTAssertEqual(app.textFields["review.label"].value as? String, "Kantor")
    }

    /// At the largest text size the sheet opens, and its rows further down are reached by scrolling.
    @MainActor
    func testEditAtTheLargestTextSize() throws {
        let app = launch(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        open(app, samples: 1, tile: "Saya")
        openEdit(app)
        XCTAssertTrue(app.textFields["review.label"].waitForExistence(timeout: 5))
        screenshot("93 edit largest text")
        let save = app.buttons["review.save"]
        XCTAssertTrue(save.exists)
        XCTAssertFalse(save.isEnabled)
    }
}
