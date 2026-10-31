//
//  ReviewUITests.swift
//  SimpaninUITests
//
//  Created by Inez Amanda on 18/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import XCTest

final class ReviewUITests: UITestCase {
    /// The model keeps 8 digits; the field has to show the same, not the digits typed past them.
    @MainActor
    func testABirthDateStopsAtEightDigits() throws {
        let app = launch(["-SimpaninUITestScan"])
        openReview(app)
        let field = app.textFields["review.field.birthDate"]
        field.tap()
        // One key at a time, as a person types: a whole string arrives faster than the field writes its
        // formatted text back, and keys get lost in a way no typing hand can cause.
        for _ in 0..<12 { field.typeText(XCUIKeyboardKey.delete.rawValue) }
        XCTAssertEqual(field.placeholderValue, "dd-mm-yyyy")
        for digit in "120420021234" { field.typeText(String(digit)) }
        XCTAssertEqual(field.value as? String, "12-04-2002")
    }

    /// The number pad has no Return, so Selesai in the navigation bar is the way to close it.
    @MainActor
    func testTheNumberPadCanBeClosed() throws {
        let app = launch(["-SimpaninUITestScan"])
        openReview(app)
        app.textFields["review.field.nik"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        app.navigationBars.buttons["review.done"].tap()
        let closed = NSPredicate(format: "exists == false")
        expectation(for: closed, evaluatedWith: app.keyboards.firstMatch)
        waitForExpectations(timeout: 5)
    }

    /// Selesai sits in the navigation bar while any field is being edited, as the number pad has no Return;
    /// Return moves on where there is one, and Simpan waits below until typing is done.
    @MainActor
    func testTheKeyboardFitsEachField() throws {
        let app = launch(["-SimpaninUITestScan"])
        openReview(app)
        let label = app.textFields["review.label"]
        // The bar's right slot: Pindai ulang, and Selesai instead while a field is being edited.
        XCTAssertFalse(app.navigationBars.buttons["review.done"].exists)
        XCTAssertTrue(app.navigationBars.buttons["review.rescan"].exists)
        label.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars.buttons["review.done"].exists)
        XCTAssertFalse(app.navigationBars.buttons["review.rescan"].exists)
        XCTAssertFalse(app.buttons["review.save"].exists)
        label.typeText("\n")
        let nik = app.textFields["review.field.nik"]
        let focused = NSPredicate(format: "hasKeyboardFocus == true")
        expectation(for: focused, evaluatedWith: nik)
        waitForExpectations(timeout: 5)
        app.navigationBars.buttons["review.done"].tap()
        XCTAssertTrue(app.buttons["review.save"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        XCTAssertFalse(app.navigationBars.buttons["review.done"].exists)
        XCTAssertTrue(app.navigationBars.buttons["review.rescan"].exists)
    }

    /// Each page is read as its number, never as an image, so VoiceOver can't offer to describe the card.
    @MainActor
    func testEachPageIsReadAsItsNumber() throws {
        let app = launch(["-SimpaninUITestScan"])
        openReview(app)
        let page = app.descendants(matching: .any)["review.page.1"]
        XCTAssertTrue(page.exists)
        XCTAssertEqual(page.label, "Halaman 1 dari 1")
        XCTAssertFalse(app.images["review.page.1"].exists)
        XCTAssertTrue(app.staticTexts["1 halaman"].exists)
    }

    /// A NIK of the wrong length says why when its field is left, and Simpan goes back to it.
    @MainActor
    func testSimpanGoesBackToAWrongNIK() throws {
        let app = launch(["-SimpaninUITestScan"])
        openReview(app)
        let nik = app.textFields["review.field.nik"]
        replace(nik, with: "00123")
        app.navigationBars.buttons["review.done"].tap()
        XCTAssertTrue(app.staticTexts["NIK harus 16 angka."].waitForExistence(timeout: 5))
        app.buttons["review.save"].tap()
        expectation(for: NSPredicate(format: "hasKeyboardFocus == true"), evaluatedWith: nik)
        waitForExpectations(timeout: 5)
        // The reason stays when the cursor goes back to the field.
        XCTAssertTrue(app.staticTexts["NIK harus 16 angka."].exists)
        // VoiceOver reads the reason with the field's name, wherever it lands on it.
        XCTAssertEqual(nik.label, "NIK, perlu diperbaiki: NIK harus 16 angka.")
    }

    /// An empty NIK is asked about: Isi NIK goes back to it, Simpan saja saves without it.
    @MainActor
    func testAnEmptyNIKIsAskedAbout() throws {
        let app = launch(["-SimpaninUITestScan"])
        openReview(app)
        let nik = app.textFields["review.field.nik"]
        replace(nik, with: "")
        app.navigationBars.buttons["review.done"].tap()
        app.buttons["review.save"].tap()
        XCTAssertTrue(app.buttons["Isi NIK"].waitForExistence(timeout: 5))
        screenshot("28 empty NIK")
        app.buttons["Isi NIK"].tap()
        expectation(for: NSPredicate(format: "hasKeyboardFocus == true"), evaluatedWith: nik)
        waitForExpectations(timeout: 5)
        app.navigationBars.buttons["review.done"].tap()
        app.buttons["review.save"].tap()
        app.buttons["Simpan saja"].tap()
        XCTAssertTrue(rows(app).firstMatch.waitForExistence(timeout: 10))
    }

    /// An STNK's date is its yearly tax: its own label and hint, and an empty one isn't marked, as no
    /// parser reads an STNK yet.
    @MainActor
    func testAnSTNKAsksForItsTaxDate() throws {
        let app = launch(["-SimpaninUITestScan"])
        openReview(app)
        app.buttons["review.type"].tap()
        app.buttons["typePicker.stnk"].tap()
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["Pajak berlaku sampai"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Tanggal pajak tahunan, bukan masa berlaku STNK 5 tahun."].exists)
        XCTAssertTrue(app.staticTexts["Belum diisi"].exists)
        let marks = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Periksa lagi"))
        XCTAssertEqual(marks.count, 0)
        screenshot("29 STNK tax date")
    }

    /// At the largest text size the pages and the bar still fit, and nothing falls off the screen.
    @MainActor
    func testPeriksaDataAtTheLargestTextSize() throws {
        let app = launch([
            "-SimpaninUITestScan", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
        ])
        // The fields sit far below at this size, and a form builds its rows only as they scroll in, so the
        // review is found by its first page.
        startScan(app)
        XCTAssertTrue(app.descendants(matching: .any)["review.page.1"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["review.page.1"].isHittable)
        XCTAssertTrue(app.navigationBars.buttons["review.rescan"].isHittable)
        XCTAssertTrue(app.buttons["review.type"].exists)
        screenshot("30 periksa data at the largest text size")
    }

    @MainActor
    func testCancellingAScanSavesNothing() throws {
        let app = launch(["-SimpaninUITestScan"])
        openReview(app)
        // Batal throws the scan away, so it asks first; Lanjut periksa keeps it.
        app.buttons["review.cancel"].tap()
        XCTAssertTrue(app.buttons["Lanjut periksa"].waitForExistence(timeout: 5))
        app.buttons["Lanjut periksa"].tap()
        XCTAssertTrue(app.textFields["review.field.name"].waitForExistence(timeout: 5))
        app.buttons["review.cancel"].tap()
        app.buttons["Buang"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["list.empty"].waitForExistence(timeout: 5))
        XCTAssertEqual(rows(app).count, 0)
    }

    /// A save takes a moment, a few seconds for photos, so Simpan says it's working until it's done.
    @MainActor
    func testSimpanSaysItsSaving() throws {
        let app = launch(["-SimpaninUITestScan", "-SimpaninUITestSlowSave"])
        openReview(app)
        app.buttons["review.save"].tap()
        XCTAssertTrue(app.buttons["Menyimpan…"].waitForExistence(timeout: 5))
        // A second tap while it saves never saves twice.
        app.buttons["review.save"].tap()
        screenshot("64 simpan while saving")
        // The list stays under Periksa data, so the save is done once its new row is there.
        XCTAssertTrue(rows(app).firstMatch.waitForExistence(timeout: 15))
        XCTAssertEqual(rows(app).count, 1)
    }

    @MainActor
    func testALabelThatLooksLikeANumberWarns() throws {
        let app = launch(["-SimpaninUITestScan"])
        openReview(app)
        app.textFields["review.label"].tap()
        app.textFields["review.label"].typeText("0012 3417 0890")
        XCTAssertTrue(app.descendants(matching: .any)["review.labelIsNumber"].waitForExistence(timeout: 5))
        screenshot("22 a label that looks like a number")
    }

    @MainActor
    func testPickingASIMClassShowsItsFields() throws {
        let app = launch(["-SimpaninUITestScan"])
        openReview(app)
        app.buttons["review.type"].tap()
        app.buttons["typePicker.sim"].tap()
        XCTAssertTrue(app.buttons["typePicker.sim-c"].waitForExistence(timeout: 5))
        screenshot("24 SIM classes")
        app.buttons["typePicker.sim-c"].tap()
        XCTAssertTrue(app.textFields["review.field.simNumber"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["review.field.nik"].exists)
        // A form builds its rows as they scroll in, and the expiry is the last one.
        app.swipeUp()
        XCTAssertTrue(app.descendants(matching: .any)["review.expiry"].waitForExistence(timeout: 5))
        // The synthetic KTP has no expiry, so the SIM's shows as missing, never as today.
        XCTAssertTrue(app.staticTexts["Belum diisi"].exists)
        // Opening the calendar sets nothing: only Pilih does, so Batal leaves it missing.
        app.descendants(matching: .any)["review.expiry"].tap()
        XCTAssertTrue(app.buttons["review.expiryCancel"].waitForExistence(timeout: 5))
        screenshot("27 expiry calendar")
        app.buttons["review.expiryCancel"].tap()
        XCTAssertTrue(app.staticTexts["Belum diisi"].waitForExistence(timeout: 5))
    }
}
