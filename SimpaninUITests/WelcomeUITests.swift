//
//  WelcomeUITests.swift
//  SimpaninUITests
//
//  Created by Inez Amanda on 3/11/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import XCTest

/// The welcome screen, on a throwaway vault folder that starts empty.
final class WelcomeUITests: UITestCase {
    @MainActor
    func launchWelcome(_ arguments: [String] = []) -> XCUIApplication {
        let app = launch(["-SimpaninUITestWelcome"] + arguments)
        XCTAssertTrue(app.staticTexts["welcome.title"].waitForExistence(timeout: 10))
        return app
    }

    @MainActor
    func expectEmptyList(_ app: XCUIApplication) {
        XCTAssertTrue(app.descendants(matching: .any)["list.empty"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["welcome.title"].exists)
    }

    @MainActor
    func testNantiSajaLandsOnTheEmptyList() throws {
        let app = launchWelcome()
        screenshot("80 welcome")
        app.buttons["welcome.later"].tap()
        expectEmptyList(app)
    }

    @MainActor
    func testPindaiDokumenOpensTheCamera() throws {
        let app = launchWelcome(["-SimpaninUITestScan"])
        app.buttons["welcome.scan"].tap()
        XCTAssertTrue(app.textFields["review.field.name"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testPilihDariFotoOpensThePicker() throws {
        let app = launchWelcome(["-SimpaninUITestPickPhotos", "ktp"])
        app.buttons["welcome.photos"].tap()
        XCTAssertTrue(app.buttons["photos.add"].waitForExistence(timeout: 10))
    }

    /// Without the document camera, Pilih dari Foto takes the primary place, above Nanti saja.
    @MainActor
    func testWithoutTheCameraPilihDariFotoIsThePrimaryButton() throws {
        let app = launchWelcome(["-SimpaninUITestNoCamera"])
        XCTAssertFalse(app.buttons["welcome.scan"].exists)
        let photos = app.buttons["welcome.photos"]
        let later = app.buttons["welcome.later"]
        XCTAssertTrue(photos.exists && later.exists)
        XCTAssertLessThan(photos.frame.minY, later.frame.minY)
        screenshot("81 welcome without the camera")
    }

    @MainActor
    func testBatalOnTheFirstScanLeavesTheEmptyList() throws {
        let app = launchWelcome(["-SimpaninUITestScan"])
        app.buttons["welcome.scan"].tap()
        XCTAssertTrue(app.textFields["review.field.name"].waitForExistence(timeout: 10))
        app.buttons["review.cancel"].tap()
        app.buttons["Buang"].tap()
        expectEmptyList(app)
    }

    @MainActor
    func testBatalInTheFirstPhotoPickLeavesTheEmptyList() throws {
        let app = launchWelcome(["-SimpaninUITestPickPhotos", "ktp"])
        app.buttons["welcome.photos"].tap()
        XCTAssertTrue(app.buttons["photos.cancel"].waitForExistence(timeout: 10))
        app.buttons["photos.cancel"].tap()
        expectEmptyList(app)
    }

    /// The title is there to start on. XCUITest's element order isn't VoiceOver's reading order, so the first
    /// focus is checked on a device.
    @MainActor
    func testTheTitleIsShown() throws {
        let app = launchWelcome()
        XCTAssertTrue(app.staticTexts["welcome.title"].isHittable)
    }

    @MainActor
    func testWelcomeAtTheLargestTextSize() throws {
        let app = launchWelcome(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        for button in ["welcome.scan", "welcome.photos", "welcome.later"] {
            XCTAssertTrue(app.buttons[button].isHittable, button)
        }
        let lastPoint = app.staticTexts[
            "Dokumen hanya ada di HP ini. Kalau HP hilang, ganti, atau Simpanin dihapus, dokumennya ikut hilang."]
        app.scrollViews.firstMatch.swipeUp()
        XCTAssertTrue(lastPoint.waitForExistence(timeout: 5))
        screenshot("82 welcome at the largest text size")
    }

    @MainActor
    func testWelcomeInDarkMode() throws {
        _ = launchWelcome()
        darkScreenshot("83 welcome in dark mode")
    }
}
