//
//  PhotoImportUITests.swift
//  SimpaninUITests
//
//  Created by Inez Amanda on 31/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import XCTest

/// Pilih dari Foto, with a synthetic photo already ticked: UI tests can't drive the system picker.
final class PhotoImportUITests: UITestCase {
    @MainActor
    func openPicker(_ mode: String) -> XCUIApplication {
        let app = launch(["-SimpaninUITestPickPhotos", mode])
        XCTAssertTrue(app.navigationBars["Dokumen"].waitForExistence(timeout: 10))
        app.buttons["list.scan"].tap()
        app.buttons["list.scan.photos"].tap()
        XCTAssertTrue(app.buttons["photos.add"].waitForExistence(timeout: 10))
        return app
    }

    /// Tambah reads the photo like a scan; Periksa data says the original stays in Photos, and it saves.
    @MainActor
    func testPickedPhotosOpenReview() throws {
        let app = openPicker("ktp")
        app.buttons["photos.add"].tap()
        XCTAssertTrue(app.textFields["review.field.name"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Foto aslinya masih ada di app Foto."].exists)
        XCTAssertEqual(app.navigationBars.buttons["review.rescan"].label, "Pilih foto lain")
        screenshot("66 periksa data from photos")
        app.buttons["review.save"].tap()
        XCTAssertTrue(rows(app).firstMatch.waitForExistence(timeout: 15))
        XCTAssertEqual(rows(app).count, 1)
    }

    /// A photo with no document in it still opens Periksa data, with no type chosen, so the user picks one.
    @MainActor
    func testNonDocumentPhotoHasNoType() throws {
        let app = openPicker("blank")
        app.buttons["photos.add"].tap()
        let type = app.buttons["review.type"]
        XCTAssertTrue(type.waitForExistence(timeout: 10))
        XCTAssertTrue(type.label.contains("Lainnya"), type.label)
        XCTAssertTrue(type.label.contains("jenis dokumen tidak dikenali"), type.label)
        screenshot("69 foto tanpa dokumen")
    }

    /// Pilih foto lain opens the picker with nothing ticked; Batal there goes back to the photo already added.
    /// UI tests can't tick a photo in the system picker, so replacing the pages is left to the model's tests.
    @MainActor
    func testPickAgainOpensPickerAndBatalKeepsPages() throws {
        let app = openPicker("ktp")
        app.buttons["photos.add"].tap()
        XCTAssertTrue(app.textFields["review.field.name"].waitForExistence(timeout: 10))
        app.navigationBars.buttons["review.rescan"].tap()
        XCTAssertTrue(app.buttons["photos.add"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["photos.add"].isEnabled)
        app.buttons["photos.cancel"].tap()
        XCTAssertTrue(app.textFields["review.field.name"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["review.field.name"].value as? String, "BUDI C0NTOH")
    }

    /// Typed changes would be lost to another photo, so Pilih foto lain asks first, in the photos' words.
    @MainActor
    func testPickAgainAsksWhenChanged() throws {
        let app = openPicker("ktp")
        app.buttons["photos.add"].tap()
        replace(app.textFields["review.field.name"], with: "TYPED")
        app.navigationBars.buttons["review.done"].tap()
        app.navigationBars.buttons["review.rescan"].tap()
        XCTAssertTrue(
            app.staticTexts["Perubahan yang kamu buat akan diganti foto yang baru dipilih."]
                .waitForExistence(timeout: 5))
        screenshot("70 pilih foto lain after typing")
    }

    /// Batal asks before throwing the photo away and says the original stays in Photos; Buang adds nothing.
    @MainActor
    func testBatalAsksWithPhotosWording() throws {
        let app = openPicker("ktp")
        app.buttons["photos.add"].tap()
        XCTAssertTrue(app.textFields["review.field.name"].waitForExistence(timeout: 10))
        app.buttons["review.cancel"].tap()
        XCTAssertTrue(app.staticTexts["Buang tanpa menyimpan?"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Foto aslinya tetap ada di app Foto."].exists)
        screenshot("71 buang foto")
        app.buttons["Buang"].tap()
        XCTAssertTrue(app.staticTexts["list.empty"].waitForExistence(timeout: 5))
        XCTAssertEqual(rows(app).count, 0)
    }

    /// A lock after Tambah drops the photo and says so in the photos' words, after the unlock.
    @MainActor
    func testLockDropsPhotoImport() throws {
        let app = launch(["-SimpaninUITestPickPhotos", "ktp"])
        lockImmediately(app)
        XCTAssertTrue(app.navigationBars["Dokumen"].waitForExistence(timeout: 10))
        app.buttons["list.scan"].tap()
        app.buttons["list.scan.photos"].tap()
        app.buttons["photos.add"].tap()
        XCTAssertTrue(app.textFields["review.field.name"].waitForExistence(timeout: 10))

        XCUIDevice.shared.press(.home)
        // Coming back locks the vault; in UI tests the unlock prompt that follows succeeds by itself.
        app.activate()
        let notice = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'Dokumen dari Foto belum'"))
        XCTAssertTrue(notice.firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(app.textFields["review.field.name"].exists)
        XCTAssertEqual(rows(app).count, 0)
        screenshot("72 foto dropped by the lock")
    }

    /// Batal while Photos hands the photo over ends at once, and nothing is added.
    @MainActor
    func testBatalWhileLoadingEndsFlow() throws {
        let app = openPicker("slow")
        app.buttons["photos.add"].tap()
        XCTAssertTrue(app.staticTexts["photos.loading"].waitForExistence(timeout: 5))
        screenshot("67 memuat foto")
        app.buttons["photos.loadingCancel"].tap()
        XCTAssertTrue(app.staticTexts["list.empty"].waitForExistence(timeout: 5))
        XCTAssertEqual(rows(app).count, 0)
    }

    /// A photo that can't be opened adds nothing and says so; on a first pick, Oke ends the flow.
    @MainActor
    func testFailedPhotoShowsAlert() throws {
        let app = openPicker("fails")
        app.buttons["photos.add"].tap()
        let alert = app.alerts["Foto tidak bisa dibuka."]
        XCTAssertTrue(alert.waitForExistence(timeout: 10))
        screenshot("68 foto tidak bisa dibuka")
        alert.buttons["Oke"].tap()
        XCTAssertTrue(app.staticTexts["list.empty"].waitForExistence(timeout: 5))
        XCTAssertEqual(rows(app).count, 0)
    }
}
