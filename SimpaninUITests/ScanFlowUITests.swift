//
//  ScanFlowUITests.swift
//  SimpaninUITests
//
//  Created by Inez Amanda on 18/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import XCTest

final class ScanFlowUITests: UITestCase {
    @MainActor
    func testScanCheckAndSaveAKTP() throws {
        let app = launch(["-SimpaninUITestScan"])
        openReview(app)
        XCTAssertEqual(app.textFields["review.field.nik"].value as? String, "0012341708900001")
        XCTAssertEqual(app.textFields["review.field.birthDate"].value as? String, "17-08-1990")
        // The synthetic name has a 0 for an O, so it's marked; VoiceOver reads the reason with the field.
        XCTAssertTrue(app.textFields["review.field.name"].label.contains("periksa lagi"))
        screenshot("20 review a scanned KTP")

        replace(app.textFields["review.field.name"], with: "BUDI CONTOH")
        XCTAssertEqual(app.textFields["review.field.name"].label, "Nama")
        app.textFields["review.label"].tap()
        // Return moves on to the NIK, and Selesai closes its number pad; Simpan waits until then.
        app.textFields["review.label"].typeText("Ibu\n")
        app.navigationBars.buttons["review.done"].tap()
        XCTAssertTrue(app.buttons["review.save"].waitForExistence(timeout: 5))
        app.buttons["review.save"].tap()

        XCTAssertTrue(rows(app).firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(rows(app).count, 1)
        screenshot("21 the saved KTP in the list")
    }

    /// A scan the lock interrupts is gone after unlocking, and the list says so.
    @MainActor
    func testALockDuringAScanDropsItAndSaysSo() throws {
        let app = launch(["-SimpaninUITestScan"])
        lockImmediately(app)
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

    /// A rescan may be a different card, so typed changes are confirmed before they're replaced.
    @MainActor
    func testARescanAfterTypingAsksFirst() throws {
        let app = launch(["-SimpaninUITestScan"])
        openReview(app)
        replace(app.textFields["review.field.name"], with: "TYPED")
        // Pindai ulang shares the bar's slot with Selesai, so typing has to be done first.
        app.navigationBars.buttons["review.done"].tap()
        app.navigationBars.buttons["review.rescan"].tap()
        XCTAssertTrue(
            app.staticTexts["Perubahan yang kamu buat akan diganti hasil pindaian baru."].waitForExistence(timeout: 5))
        screenshot("23 rescan after typing")
    }

    /// The same KTP scanned again asks first; Kembali keeps the scan, Simpan keeps both.
    @MainActor
    func testSavingTheSameKTPAgainAsks() throws {
        let app = launch(["-SimpaninUITestScan"])
        openReview(app)
        app.buttons["review.save"].tap()
        XCTAssertTrue(waitForRows(1, in: app))
        openReview(app)
        app.buttons["review.save"].tap()

        let alert = app.alerts["Kamu sudah punya KTP dengan NIK ini."]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertTrue(alert.staticTexts["Yang lama tidak diganti. Kalau disimpan, keduanya ada di daftar."].exists)
        screenshot("27 the same KTP saved again")
        alert.buttons["Kembali"].tap()
        XCTAssertTrue(app.buttons["review.save"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["review.field.name"].exists)
        app.buttons["review.save"].tap()
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["Simpan"].tap()
        XCTAssertTrue(waitForRows(2, in: app))
    }

    /// The pages are asked about first, then the duplicate; after Kembali only the duplicate is asked again.
    @MainActor
    func testThePagesAndDuplicateAlertsInARow() throws {
        let app = launch(["-SimpaninUITestScanKTPAndSIM"])
        let pages = app.alerts["Ada halaman dari dokumen lain"]
        openReview(app)
        app.buttons["review.save"].tap()
        XCTAssertTrue(pages.waitForExistence(timeout: 5))
        pages.buttons["Simpan"].tap()
        XCTAssertTrue(waitForRows(1, in: app))
        openReview(app)
        app.buttons["review.save"].tap()
        XCTAssertTrue(pages.waitForExistence(timeout: 5))
        pages.buttons["Simpan"].tap()

        let duplicate = app.alerts["Kamu sudah punya KTP dengan NIK ini."]
        XCTAssertTrue(duplicate.waitForExistence(timeout: 5))
        duplicate.buttons["Kembali"].tap()
        XCTAssertTrue(app.buttons["review.save"].waitForExistence(timeout: 5))
        app.buttons["review.save"].tap()
        XCTAssertTrue(duplicate.waitForExistence(timeout: 5))
        XCTAssertFalse(pages.exists)
        duplicate.buttons["Simpan"].tap()
        XCTAssertTrue(waitForRows(2, in: app))
    }

    /// The lock takes the duplicate alert with the scan; nothing more is saved.
    @MainActor
    func testALockWhileTheWarningIsOpenDropsTheScan() throws {
        let app = launch(["-SimpaninUITestScan"])
        openReview(app)
        app.buttons["review.save"].tap()
        XCTAssertTrue(waitForRows(1, in: app))
        lockImmediately(app)
        openReview(app)
        app.buttons["review.save"].tap()
        let alert = app.alerts["Kamu sudah punya KTP dengan NIK ini."]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))

        XCUIDevice.shared.press(.home)
        // Coming back locks the vault; in UI tests the unlock prompt that follows succeeds by itself.
        app.activate()
        let notice = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'Pindaian yang belum disimpan'"))
        XCTAssertTrue(notice.firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(alert.exists)
        XCTAssertEqual(rows(app).count, 1)
    }

    /// Rows can take a moment to appear after a save; checked for up to ten seconds, never forever.
    @MainActor
    private func waitForRows(_ count: Int, in app: XCUIApplication) -> Bool {
        let deadline = Date().addingTimeInterval(10)
        while rows(app).count != count, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return rows(app).count == count
    }
}
