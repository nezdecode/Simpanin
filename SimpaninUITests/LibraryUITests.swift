//
//  LibraryUITests.swift
//  SimpaninUITests
//
//  Created by Inez Amanda on 18/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import XCTest

final class LibraryUITests: UITestCase {
    @MainActor
    func testAddDeleteAndRestore() throws {
        let app = launch()
        XCTAssertTrue(app.navigationBars["Dokumen"].waitForExistence(timeout: 10))
        screenshot("01 empty list")
        for _ in 0..<3 { app.buttons["list.addSample"].tap() }
        XCTAssertTrue(rows(app).element(boundBy: 2).waitForExistence(timeout: 5))
        XCTAssertEqual(rows(app).count, 3)
        screenshot("02 list with samples")

        // The list is a grid of tiles, so deleting is in the long-press menu.
        rows(app).element(boundBy: 0).press(forDuration: 1.2)
        app.buttons["Hapus"].tap()
        XCTAssertTrue(rows(app).element(boundBy: 1).waitForExistence(timeout: 5))
        XCTAssertEqual(rows(app).count, 2)

        app.buttons["list.recentlyDeleted"].tap()
        XCTAssertTrue(rows(app).firstMatch.waitForExistence(timeout: 5))
        screenshot("03 recently deleted")
        rows(app).firstMatch.swipeLeft()
        app.buttons["Pulihkan"].tap()
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(rows(app).element(boundBy: 2).waitForExistence(timeout: 5))
        XCTAssertEqual(rows(app).count, 3)
    }

    /// A list that couldn't load says so, never "Belum ada dokumen", and "+" waits until it loads.
    @MainActor
    func testAFailedLoadSaysSoAndRetryWorks() throws {
        // Two failing loads: the first at launch, the second when the list appears again after Settings.
        let app = launch(["-SimpaninUITestLoadError", "2"])
        let failed = app.descendants(matching: .any)["load.failed"]
        XCTAssertTrue(failed.waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["list.empty"].exists)
        XCTAssertFalse(app.buttons["list.addSample"].isEnabled)
        screenshot("11 dokumen tidak bisa dimuat")

        // One screen deeper, Baru dihapus mustn't claim to be empty either.
        app.buttons["list.settings"].tap()
        let bin = app.buttons["settings.recentlyDeleted"]
        XCTAssertTrue(bin.waitForExistence(timeout: 5))
        XCTAssertFalse(bin.label.contains("0"), "Baru dihapus in Settings: \(bin.label)")
        bin.tap()
        XCTAssertTrue(app.descendants(matching: .any)["load.failed"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.navigationBars["Pengaturan"].buttons.element(boundBy: 0).tap()

        app.buttons["load.retry"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["list.empty"].waitForExistence(timeout: 5))
        XCTAssertFalse(failed.exists)
        XCTAssertTrue(app.buttons["list.addSample"].isEnabled)
    }

    /// The banner's … menu takes a document out of the banner: the next one shows, and with none left, no
    /// banner at all. The tiles stay.
    @MainActor
    func testTheBannerMenuButtonHides() throws {
        let app = launch(["-SimpaninUITestExpiringSamples"])
        // The first sample is a KTP, which has no date, so it's never in the banner.
        for _ in 0..<3 { app.buttons["list.addSample"].tap() }
        XCTAssertTrue(app.staticTexts["dan 1 dokumen lain perlu dicek"].waitForExistence(timeout: 5))
        screenshot("31 banner with two")
        app.buttons["banner.menu"].tap()
        app.buttons["Jangan tampilkan di sini"].tap()
        XCTAssertTrue(app.buttons["banner.menu"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["dan 1 dokumen lain perlu dicek"].exists)
        app.buttons["banner.menu"].tap()
        app.buttons["Jangan tampilkan di sini"].tap()
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: app.buttons["banner.menu"])
        waitForExpectations(timeout: 5)
        XCTAssertEqual(rows(app).count, 3)
    }

    /// A long press on the banner offers the same.
    @MainActor
    func testTheBannerCanBeHidden() throws {
        let app = launch(["-SimpaninUITestExpiringSamples"])
        // A KTP and a SIM A: only the SIM has a date.
        for _ in 0..<2 { app.buttons["list.addSample"].tap() }
        let banner = app.descendants(matching: .any)["banner"]
        XCTAssertTrue(banner.waitForExistence(timeout: 5))
        banner.press(forDuration: 1)
        app.buttons["Jangan tampilkan di sini"].tap()
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: banner)
        waitForExpectations(timeout: 5)
    }

    @MainActor
    func testTheBannerAtTheLargestTextSize() throws {
        let app = launch([
            "-SimpaninUITestExpiringSamples", "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL",
        ])
        XCTAssertTrue(app.buttons["list.addSample"].waitForExistence(timeout: 10))
        for _ in 0..<2 { app.buttons["list.addSample"].tap() }
        XCTAssertTrue(app.buttons["banner.menu"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["banner.menu"].isHittable)
        screenshot("32 banner at the largest text size")
    }

    /// Pilih dari Foto opens the picker and nothing else: no camera, and no camera permission prompt. Ticking
    /// photos isn't adding them, so a lock before Tambah drops nothing and says nothing.
    @MainActor
    func testPilihDariFotoStartsNothingBeforeTambah() throws {
        let app = launch(["-SimpaninUITestScan"])
        app.buttons["list.settings"].tap()
        let row = app.buttons["settings.autoLock"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        app.buttons["autoLock.immediately"].tap()
        app.navigationBars["Kunci otomatis"].buttons.element(boundBy: 0).tap()
        app.navigationBars["Pengaturan"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Dokumen"].waitForExistence(timeout: 10))
        app.buttons["list.scan"].tap()
        app.buttons["list.scan.photos"].tap()
        XCTAssertTrue(app.buttons["photos.add"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["photos.add"].isEnabled)
        screenshot("65 pilih dari foto")

        XCUIDevice.shared.press(.home)
        // Coming back locks the vault; in UI tests the unlock prompt that follows succeeds by itself.
        app.activate()
        XCTAssertTrue(app.staticTexts["list.empty"].waitForExistence(timeout: 10))
        let notices = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH 'Pindaian yang belum' OR label BEGINSWITH 'Dokumen dari Foto'"))
        XCTAssertEqual(notices.count, 0)
        XCTAssertFalse(app.textFields["review.field.name"].exists)
    }
}
