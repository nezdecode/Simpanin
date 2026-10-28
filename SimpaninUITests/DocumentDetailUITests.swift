//
//  DocumentDetailUITests.swift
//  SimpaninUITests
//
//  Created by Inez Amanda on 28/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import XCTest

/// The document screen, on the DEBUG samples: in turn a KTP "Saya", a SIM A with two pages, a passport, an
/// older SIM C "Ibu" and a KTP without a NIK. Their numbers start with 00.
final class DocumentDetailUITests: UITestCase {
    @MainActor
    func testOpenFromTile() throws {
        let app = launch()
        open(app, samples: 1, tile: "Saya")
        XCTAssertTrue(app.navigationBars["KTP"].exists)
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Saya · ditambahkan '")).firstMatch.exists)
        XCTAssertEqual(field(app, "name").value as? String, "CONTOH 1")
        XCTAssertEqual(field(app, "birthDate").value as? String, "17-08-1990")
        XCTAssertTrue(app.descendants(matching: .any)["detail.validity"].label.contains("Seumur hidup"))
        screenshot("40 document KTP")
        darkScreenshot("41 document KTP dark")
    }

    @MainActor
    func testTappingTheBannerOpensTheDocument() throws {
        let app = launch(["-SimpaninUITestExpiringSamples"])
        addSamples(app, 2)
        let banner = app.descendants(matching: .any)["banner"]
        XCTAssertTrue(banner.waitForExistence(timeout: 5))
        banner.tap()
        XCTAssertTrue(app.navigationBars["SIM A"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["detail.validity"].label.contains("Habis dalam"))
    }

    /// The masked number holds no hidden digit, on screen or for VoiceOver.
    @MainActor
    func testRevealAndHideNumber() throws {
        let app = launch()
        open(app, samples: 1, tile: "Saya")
        let nik = field(app, "nik")
        XCTAssertEqual(nik.value as? String, "tersembunyi")
        XCTAssertTrue(app.staticTexts["0000 •••• •••• 0001"].exists)
        XCTAssertFalse(app.staticTexts["0000 0000 0000 0001"].exists)
        app.buttons["detail.reveal"].tap()
        XCTAssertEqual(nik.value as? String, "0000 0000 0000 0001")
        XCTAssertEqual(app.buttons["detail.reveal"].label, "Sembunyikan NIK")
        screenshot("42 document NIK shown")
        app.buttons["detail.reveal"].tap()
        XCTAssertEqual(nik.value as? String, "tersembunyi")
        XCTAssertEqual(app.buttons["detail.reveal"].label, "Tampilkan NIK")
    }

    @MainActor
    func testOlderSIMShowsDashes() throws {
        let app = launch()
        open(app, samples: 4, tile: "Ibu")
        XCTAssertTrue(app.staticTexts["0000-••••-••0004"].exists)
        app.buttons["detail.reveal"].tap()
        XCTAssertEqual(field(app, "simNumber").value as? String, "0000-0000-000004")
        XCTAssertEqual(app.buttons["detail.reveal"].label, "Sembunyikan nomor SIM")
    }

    @MainActor
    func testEmptyNIKShowsBelumDiisi() throws {
        let app = launch()
        addSamples(app, 5)
        tile(app, "KTP", without: "Saya").tap()
        let nik = field(app, "nik")
        XCTAssertTrue(nik.waitForExistence(timeout: 5))
        XCTAssertEqual(nik.value as? String, "NIK belum diisi")
        XCTAssertFalse(app.buttons["detail.reveal"].exists)
        XCTAssertFalse(app.buttons["detail.copy.nik"].exists)
    }

    @MainActor
    func testCopyShowsToast() throws {
        let app = launch()
        open(app, samples: 1, tile: "Saya")
        app.buttons["detail.copy.nik"].tap()
        let toast = app.descendants(matching: .any)["toast"]
        XCTAssertTrue(toast.waitForExistence(timeout: 2))
        XCTAssertTrue(toast.label.contains("NIK disalin"))
        XCTAssertFalse(toast.label.contains("0001"))
        // Copying doesn't show the number.
        XCTAssertEqual(field(app, "nik").value as? String, "tersembunyi")
        screenshot("43 document copied")
    }

    @MainActor
    func testTwoPagesSwipe() throws {
        let app = launch()
        open(app, samples: 2, tile: "SIM A")
        let first = app.buttons["detail.page.1"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertEqual(first.label, "Halaman 1 dari 2")
        first.swipeLeft()
        XCTAssertTrue(app.buttons["detail.page.2"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["detail.page.2"].isHittable)
    }

    /// Opening the viewer masks the number again.
    @MainActor
    func testEnlargePageAndClose() throws {
        let app = launch()
        open(app, samples: 1, tile: "Saya")
        app.buttons["detail.reveal"].tap()
        let page = app.buttons["detail.page.1"]
        XCTAssertTrue(page.waitForExistence(timeout: 5))
        page.tap()
        let close = app.buttons["viewer.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        XCTAssertEqual(close.label, "Tutup")
        screenshot("44 page enlarged")
        close.tap()
        XCTAssertTrue(page.waitForExistence(timeout: 5))
        XCTAssertFalse(close.exists)
        XCTAssertEqual(field(app, "nik").value as? String, "tersembunyi")
    }

    @MainActor
    func testPageHasNoContextMenu() throws {
        let app = launch()
        open(app, samples: 1, tile: "Saya")
        let page = app.buttons["detail.page.1"]
        XCTAssertTrue(page.waitForExistence(timeout: 5))
        page.press(forDuration: 1.5)
        XCTAssertFalse(app.buttons["Salin"].exists)
        XCTAssertFalse(app.buttons["Bagikan"].exists)
        XCTAssertFalse(app.buttons["Copy"].exists)
    }

    @MainActor
    func testRevealedNumberIsMaskedAfterTheBackground() throws {
        let app = launch()
        open(app, samples: 1, tile: "Saya")
        app.buttons["detail.reveal"].tap()
        XCTAssertEqual(field(app, "nik").value as? String, "0000 0000 0000 0001")
        // Kunci otomatis is a minute, so the screen is still there on return.
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(field(app, "nik").waitForExistence(timeout: 10))
        XCTAssertEqual(field(app, "nik").value as? String, "tersembunyi")
    }

    @MainActor
    func testLockWhileTheDocumentIsOpenReturnsToTheList() throws {
        let app = launch()
        lockImmediately(app)
        open(app, samples: 1, tile: "Saya")
        XCUIDevice.shared.press(.home)
        // Coming back locks the vault; in UI tests the unlock prompt that follows succeeds by itself.
        app.activate()
        XCTAssertTrue(rows(app).firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(field(app, "nik").exists)
    }

    @MainActor
    func testLockWhileThePageViewerIsOpenReturnsToTheList() throws {
        let app = launch()
        lockImmediately(app)
        open(app, samples: 1, tile: "Saya")
        app.buttons["detail.page.1"].tap()
        XCTAssertTrue(app.buttons["viewer.close"].waitForExistence(timeout: 5))
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(rows(app).firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["viewer.close"].exists)
        XCTAssertFalse(field(app, "nik").exists)
    }

    @MainActor
    func testTampilkanLagiBringsItBackToTheBanner() throws {
        let app = launch(["-SimpaninUITestExpiringSamples"])
        addSamples(app, 2)
        app.buttons["banner.menu"].tap()
        app.buttons["Jangan tampilkan di sini"].tap()
        let banner = app.descendants(matching: .any)["banner"]
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: banner)
        waitForExpectations(timeout: 5)
        tile(app, "SIM A").tap()
        let showAgain = app.buttons["detail.showInBanner"]
        XCTAssertTrue(showAgain.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Tidak tampil di banner masa berlaku."].exists)
        screenshot("45 document hidden from the banner")
        showAgain.tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: showAgain)
        waitForExpectations(timeout: 5)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(banner.waitForExistence(timeout: 5))
    }

    @MainActor
    func testDeleteReturnsToList() throws {
        let app = launch()
        open(app, samples: 2, tile: "Saya")
        app.buttons["detail.delete"].tap()
        XCTAssertTrue(app.navigationBars["Dokumen"].waitForExistence(timeout: 5))
        XCTAssertFalse(field(app, "nik").exists)
        XCTAssertEqual(rows(app).count, 1)
        XCTAssertTrue(app.buttons["list.recentlyDeleted"].label.contains("1"))
    }

    @MainActor
    func testDeleteSaysWhereItWent() throws {
        let app = launch()
        open(app, samples: 1, tile: "Saya")
        app.buttons["detail.delete"].tap()
        let toast = app.descendants(matching: .any)["toast"]
        XCTAssertTrue(toast.waitForExistence(timeout: 5))
        XCTAssertEqual(toast.label, "Dipindahkan ke Baru dihapus.")
        screenshot("46 deleted from the document")
    }

    @MainActor
    func testTheDocumentAtTheLargestTextSize() throws {
        let app = launch(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        open(app, samples: 1, tile: "Saya")
        screenshot("47 document at the largest text size")
        app.swipeUp()
        XCTAssertTrue(app.buttons["detail.reveal"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["detail.reveal"].isHittable)
        screenshot("48 document fields at the largest text size")
    }

    // MARK: Helpers

    @MainActor
    private func addSamples(_ app: XCUIApplication, _ count: Int) {
        XCTAssertTrue(app.buttons["list.addSample"].waitForExistence(timeout: 10))
        for _ in 0..<count { app.buttons["list.addSample"].tap() }
        XCTAssertTrue(rows(app).element(boundBy: count - 1).waitForExistence(timeout: 5))
    }

    @MainActor
    private func open(_ app: XCUIApplication, samples: Int, tile text: String) {
        addSamples(app, samples)
        tile(app, text).tap()
        // The top of the screen: at the largest text size the rows further down aren't built until scrolled to.
        XCTAssertTrue(app.buttons["detail.page.1"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func tile(_ app: XCUIApplication, _ text: String, without other: String? = nil) -> XCUIElement {
        let format = other == nil ? "label CONTAINS %@" : "label CONTAINS %@ AND NOT (label CONTAINS %@)"
        return rows(app).matching(NSPredicate(format: format, argumentArray: [text, other ?? ""])).firstMatch
    }

    @MainActor
    private func field(_ app: XCUIApplication, _ key: String) -> XCUIElement {
        app.descendants(matching: .any)["detail.field.\(key)"]
    }

    @MainActor
    private func lockImmediately(_ app: XCUIApplication) {
        app.buttons["list.settings"].tap()
        let row = app.buttons["settings.autoLock"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        app.buttons["autoLock.immediately"].tap()
        app.navigationBars["Kunci otomatis"].buttons.element(boundBy: 0).tap()
        app.navigationBars["Pengaturan"].buttons.element(boundBy: 0).tap()
    }
}
