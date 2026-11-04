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

/// The document screen's fields, Berlaku, the banner's way in and back, Hapus and the lock, on the DEBUG samples.
final class DocumentDetailUITests: UITestCase {
    @MainActor
    func testOpenFromTile() throws {
        let app = launch()
        addSamples(app, 1)
        // VoiceOver reads a tile as a button.
        XCTAssertTrue(app.buttons.matching(identifier: "document.row").firstMatch.exists)
        open(app, samples: 0, tile: "Saya")
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
        let added = NSPredicate(format: "label BEGINSWITH 'Ditambahkan '")
        XCTAssertTrue(app.staticTexts.matching(added).firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any)["detail.validity"].label.contains("Habis dalam"))
    }

    /// The whole banner opens the document it names, its "dan N dokumen lain" line too.
    @MainActor
    func testTheBannerCountLineOpensTheNamedDocument() throws {
        let app = launch(["-SimpaninUITestExpiringSamples"])
        addSamples(app, 3)
        XCTAssertTrue(app.staticTexts["dan 1 dokumen lain perlu dicek"].waitForExistence(timeout: 5))
        // The banner is one element for VoiceOver, so a tap on it lands in its middle; the count line is its last.
        app.descendants(matching: .any)["banner"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)).tap()
        XCTAssertTrue(app.navigationBars["SIM A"].waitForExistence(timeout: 5))
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
        XCTAssertEqual(nik.value as? String, "Belum diisi")
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
        scrolledTo(app, "detail.delete").tap()
        XCTAssertTrue(app.navigationBars["Dokumen"].waitForExistence(timeout: 5))
        XCTAssertFalse(field(app, "nik").exists)
        XCTAssertEqual(rows(app).count, 1)
        XCTAssertTrue(app.buttons["list.recentlyDeleted"].label.contains("1"))
    }

    @MainActor
    func testDeleteSaysWhereItWent() throws {
        let app = launch()
        open(app, samples: 1, tile: "Saya")
        scrolledTo(app, "detail.delete").tap()
        let toast = app.descendants(matching: .any)["toast"]
        XCTAssertTrue(toast.waitForExistence(timeout: 5))
        XCTAssertEqual(toast.label, "Dipindahkan ke Baru dihapus.")
        screenshot("46 deleted from the document")
    }

    /// The list's save alert shows over the document, which stays open.
    @MainActor
    func testFailedDeleteStaysOnTheDocumentWithTheAlert() throws {
        let app = launch(["-SimpaninUITestDeleteError"])
        open(app, samples: 1, tile: "Saya")
        scrolledTo(app, "detail.delete").tap()
        let alert = app.alerts["Perubahan belum tersimpan. Coba lagi."]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        screenshot("49 delete failed")
        alert.buttons.firstMatch.tap()
        XCTAssertTrue(field(app, "nik").waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["toast"].exists)
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
}
