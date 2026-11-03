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
