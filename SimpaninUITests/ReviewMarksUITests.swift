//
//  ReviewMarksUITests.swift
//  SimpaninUITests
//
//  Created by Inez Amanda on 19/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import XCTest

/// Periksa data's marks, refusals and "Cocok dengan tanggal lahir". The synthetic KTP's name has a 0 for
/// an O, and its NIK agrees with its birth date. The texts under the fields are hidden from VoiceOver,
/// which reads them in the field's label, so that label is what these tests check.
final class ReviewMarksUITests: UITestCase {
    @MainActor
    func testAMarkShowsItsReasonAndVoiceOverReadsIt() throws {
        let app = launch(["-SimpaninUITestScan"])
        openReview(app)
        let name = app.textFields["review.field.name"]
        XCTAssertEqual(name.label, "Nama, periksa lagi: ada karakter yang tidak biasa untuk nama.")
        // The bar for Simpan covers the lower rows until the form is scrolled.
        app.swipeUp()
        screenshot("34 a mark with its reason")
        replace(name, with: "BUDI CONTOH")
        XCTAssertEqual(name.label, "Nama")
    }

    @MainActor
    func testARefusalIsReadWithItsField() throws {
        let app = launch(["-SimpaninUITestScan"])
        openReview(app)
        let nik = app.textFields["review.field.nik"]
        replace(nik, with: "0012341708")
        app.navigationBars.buttons["review.done"].tap()
        XCTAssertEqual(nik.label, "NIK, perlu diperbaiki: NIK harus 16 angka.")
        screenshot("35 a refusal")
    }

    @MainActor
    func testBirthDateMatchShowsAndGoesAfterAnEdit() throws {
        let app = launch(["-SimpaninUITestScan"])
        openReview(app)
        let match = app.staticTexts["review.birthDateMatch"]
        XCTAssertTrue(match.exists)
        XCTAssertEqual(match.label, "Cocok dengan tanggal lahir")
        // The last digit isn't part of the date, so the NIK still agrees; only the edit hides it.
        replace(app.textFields["review.field.nik"], with: "0012341708900002")
        XCTAssertFalse(match.exists)
    }

    /// XCUITest reads a label whole even when the screen cuts it, so the screenshot is the check here.
    @MainActor
    func testAReasonAtTheLargestTextSize() throws {
        let app = launch([
            "-SimpaninUITestScan", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
        ])
        XCTAssertTrue(app.navigationBars["Dokumen"].waitForExistence(timeout: 10))
        app.buttons["list.scan"].tap()
        let name = app.textFields["review.field.name"]
        for _ in 0..<6 where !name.exists { app.swipeUp() }
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertTrue(name.label.hasSuffix("periksa lagi: ada karakter yang tidak biasa untuk nama."))
        screenshot("36 a reason at the largest text size")
    }
}
