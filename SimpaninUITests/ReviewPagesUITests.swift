//
//  ReviewPagesUITests.swift
//  SimpaninUITests
//
//  Created by Inez Amanda on 26/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import XCTest

/// Periksa data's notes on the pages of a scan. `-SimpaninUITestScanKTPAndSIM` reads a synthetic KTP on
/// page 1 and a SIM A on page 2. A thumbnail is one element, so its badge and note are checked in its label.
final class ReviewPagesUITests: UITestCase {
    @MainActor
    func testASecondDocumentIsNotedOnItsPage() throws {
        let app = launch(["-SimpaninUITestScanKTPAndSIM"])
        openReview(app)
        XCTAssertTrue(app.staticTexts["2 halaman"].exists)
        XCTAssertTrue(app.staticTexts["Halaman 2 terbaca sebagai SIM A, bukan KTP di halaman 1."].exists)
        let page = { (number: Int) in app.descendants(matching: .any)["review.page.\(number)"] }
        XCTAssertEqual(page(1).label, "Halaman 1 dari 2, isian dibaca dari halaman ini")
        XCTAssertEqual(page(2).label, "Halaman 2 dari 2, terbaca sebagai SIM A")
        // The fields are still the KTP's.
        XCTAssertEqual(app.textFields["review.field.nik"].value as? String, "0012341708900001")
        screenshot("37 a second document in the scan")
        darkScreenshot("37 a second document in the scan, dark")
    }

    /// The notes compare with the page the fields came from; a type without a parser says what each was.
    @MainActor
    func testChangingTheTypeKeepsTheNotesOnTheSourcePage() throws {
        let app = launch(["-SimpaninUITestScanKTPAndSIM"])
        openReview(app)
        app.buttons["review.type"].tap()
        app.buttons["typePicker.stnk"].tap()
        XCTAssertTrue(app.staticTexts["Halaman 1 terbaca sebagai KTP."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Halaman 2 terbaca sebagai SIM A."].exists)
        app.buttons["review.type"].tap()
        app.buttons["typePicker.ktp"].tap()
        let note = app.staticTexts["Halaman 2 terbaca sebagai SIM A, bukan KTP di halaman 1."]
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Halaman 1 terbaca sebagai KTP."].exists)
    }

    @MainActor
    func testASingleKTPHasNoPageNotes() throws {
        let app = launch(["-SimpaninUITestScan"])
        openReview(app)
        XCTAssertEqual(app.descendants(matching: .any)["review.page.1"].label, "Halaman 1 dari 1")
        let notes = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Halaman"))
        XCTAssertEqual(notes.count, 0)
        XCTAssertFalse(app.staticTexts["Isian dibaca dari halaman 1."].exists)
    }

    /// The badge keeps its size; the footer's sentences wrap.
    @MainActor
    func testPageNotesAtTheLargestTextSize() throws {
        let app = launch([
            "-SimpaninUITestScanKTPAndSIM", "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL",
        ])
        XCTAssertTrue(app.navigationBars["Dokumen"].waitForExistence(timeout: 10))
        app.buttons["list.scan"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["review.page.2"].waitForExistence(timeout: 10))
        screenshot("38 page badges at the largest text size")
        app.swipeUp()
        screenshot("39 page notes at the largest text size")
    }
}
