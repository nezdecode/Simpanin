//
//  SimpaninUITests+Scanning.swift
//  SimpaninUITests
//
//  Created by Inez Amanda on 17/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import XCTest

extension SimpaninUITests {
    // MARK: Scanning (synthetic page and text: the simulator has no camera)

    @MainActor
    private func openReview(_ app: XCUIApplication) {
        XCTAssertTrue(app.navigationBars["Dokumen"].waitForExistence(timeout: 10))
        app.buttons["list.scan"].tap()
        XCTAssertTrue(app.textFields["review.field.name"].waitForExistence(timeout: 10))
    }

    @MainActor
    private func replace(_ field: XCUIElement, with text: String) {
        field.tap()
        let old = field.value as? String ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count) + text)
    }

    @MainActor
    func testScanCheckAndSaveAKTP() throws {
        let app = launch(["-SimpaninUITestScan"])
        openReview(app)
        XCTAssertEqual(app.textFields["review.field.nik"].value as? String, "0012341708900001")
        XCTAssertEqual(app.textFields["review.field.birthDate"].value as? String, "17-08-1990")
        // The synthetic name has a 0 for an O, so it's marked.
        XCTAssertTrue(app.staticTexts["Periksa lagi"].exists)
        screenshot("20 review a scanned KTP")

        replace(app.textFields["review.field.name"], with: "BUDI CONTOH")
        XCTAssertFalse(app.staticTexts["Periksa lagi"].exists)
        app.textFields["review.label"].tap()
        // Return moves on to the NIK, and Selesai closes its number pad; Simpan waits until then.
        app.textFields["review.label"].typeText("Ibu\n")
        app.buttons["keyboard.done"].tap()
        XCTAssertTrue(app.buttons["review.save"].waitForExistence(timeout: 5))
        app.buttons["review.save"].tap()

        XCTAssertTrue(rows(app).firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(rows(app).count, 1)
        screenshot("21 the saved KTP in the list")
    }

    /// Sheets and full-screen covers sit above the root view, so the privacy cover must too: while the
    /// screen is recorded (or the app is in the switcher), the scan's fields can't be reached, seen or read
    /// by VoiceOver.
    @MainActor
    func testTheCoverSitsAboveTheScanFlow() throws {
        let app = launch(["-SimpaninUITestScan", "-SimpaninUITestCaptureAfterScan"])
        openReview(app)
        // The recording starts with the review on screen: its fields go from the accessibility tree too, so
        // VoiceOver can't read what the cover hides.
        XCTAssertTrue(app.staticTexts["lock.title"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.textFields["review.field.nik"].exists)
        XCTAssertFalse(app.textFields["review.field.name"].exists)
        screenshot("25 cover above the scan flow")
        // When it stops, the review and its fields come back.
        XCTAssertTrue(app.textFields["review.field.nik"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["lock.title"].exists)
    }

    /// A scan the lock interrupts is gone after unlocking, and the list says so.
    @MainActor
    func testALockDuringAScanDropsItAndSaysSo() throws {
        let app = launch(["-SimpaninUITestScan"])
        app.buttons["list.settings"].tap()
        let row = app.buttons["settings.autoLock"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        app.buttons["autoLock.immediately"].tap()
        app.navigationBars["Kunci otomatis"].buttons.element(boundBy: 0).tap()
        app.navigationBars["Pengaturan"].buttons.element(boundBy: 0).tap()
        openReview(app)

        XCUIDevice.shared.press(.home)
        // Coming back locks the vault; in UI tests the unlock prompt that follows succeeds by itself.
        app.activate()
        let notice = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'Pindaian yang belum disimpan'"))
        XCTAssertTrue(notice.firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(app.textFields["review.field.name"].exists)
        XCTAssertTrue(app.staticTexts["list.empty"].exists)
        screenshot("26 scan dropped by the lock")
    }

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

    /// The number pad has no return key, so Selesai above it is the way to close it.
    @MainActor
    func testTheNumberPadCanBeClosed() throws {
        let app = launch(["-SimpaninUITestScan"])
        openReview(app)
        app.textFields["review.field.nik"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        app.buttons["keyboard.done"].tap()
        let closed = NSPredicate(format: "exists == false")
        expectation(for: closed, evaluatedWith: app.keyboards.firstMatch)
        waitForExpectations(timeout: 5)
    }

    /// Each field gets the keyboard it needs: Return moves on where there is one, Selesai only on the
    /// number pad, and Simpan waits below until typing is done.
    @MainActor
    func testTheKeyboardFitsEachField() throws {
        let app = launch(["-SimpaninUITestScan"])
        openReview(app)
        let label = app.textFields["review.label"]
        label.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["keyboard.done"].exists)
        XCTAssertFalse(app.buttons["review.save"].exists)
        label.typeText("\n")
        let nik = app.textFields["review.field.nik"]
        let focused = NSPredicate(format: "hasKeyboardFocus == true")
        expectation(for: focused, evaluatedWith: nik)
        waitForExpectations(timeout: 5)
        app.buttons["keyboard.done"].tap()
        XCTAssertTrue(app.buttons["review.save"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.keyboards.firstMatch.exists)
    }

    /// A NIK of the wrong length says why when its field is left, and Simpan goes back to it.
    @MainActor
    func testSimpanGoesBackToAWrongNIK() throws {
        let app = launch(["-SimpaninUITestScan"])
        openReview(app)
        let nik = app.textFields["review.field.nik"]
        replace(nik, with: "00123")
        app.buttons["keyboard.done"].tap()
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
        app.buttons["keyboard.done"].tap()
        app.buttons["review.save"].tap()
        XCTAssertTrue(app.buttons["Isi NIK"].waitForExistence(timeout: 5))
        screenshot("28 empty NIK")
        app.buttons["Isi NIK"].tap()
        expectation(for: NSPredicate(format: "hasKeyboardFocus == true"), evaluatedWith: nik)
        waitForExpectations(timeout: 5)
        app.buttons["keyboard.done"].tap()
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
        XCTAssertFalse(app.staticTexts["Periksa lagi"].exists)
        screenshot("29 STNK tax date")
    }

    @MainActor
    func testCancellingAScanSavesNothing() throws {
        let app = launch(["-SimpaninUITestScan"])
        openReview(app)
        app.buttons["review.cancel"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["list.empty"].waitForExistence(timeout: 5))
        XCTAssertEqual(rows(app).count, 0)
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

    /// A rescan may be a different card, so typed changes are confirmed before they're replaced.
    @MainActor
    func testARescanAfterTypingAsksFirst() throws {
        let app = launch(["-SimpaninUITestScan"])
        openReview(app)
        replace(app.textFields["review.field.name"], with: "TYPED")
        app.buttons["review.rescan"].tap()
        XCTAssertTrue(
            app.staticTexts["Perubahan yang kamu ketik akan diganti hasil pindaian baru."].waitForExistence(timeout: 5))
        screenshot("23 rescan after typing")
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
