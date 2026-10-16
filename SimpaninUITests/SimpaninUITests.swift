//
//  SimpaninUITests.swift
//  SimpaninUITests
//
//  Created by Inez Amanda on 4/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import XCTest

/// The main flows, on a fresh throwaway vault with an in-memory key, never a real vault.
/// Each screen is saved as a screenshot, for the design work.
final class SimpaninUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(_ arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-SimpaninUITest"] + arguments
        app.launch()
        return app
    }

    @MainActor
    private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func rows(_ app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: "document.row")
    }

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

    @MainActor
    func testSettingsAndOldVaults() throws {
        // A broken folder in Data lama, so Settings has a size to show next to it.
        let app = launch(["-SimpaninUITestBrokenOldVault"])
        app.buttons["list.settings"].tap()
        XCTAssertTrue(app.navigationBars["Pengaturan"].waitForExistence(timeout: 5))
        let oldVaults = app.buttons["settings.oldVaults"]
        XCTAssertTrue(oldVaults.waitForExistence(timeout: 5))
        XCTAssertTrue(oldVaults.label.contains("11"), "Data lama's size: \(oldVaults.label)")
        screenshot("04 settings")
        app.buttons["settings.oldVaults"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["oldVaults.unreadable"].waitForExistence(timeout: 5))
        screenshot("05 data lama")
    }

    /// Inez's report: Settings showed the old choice after going back and opening it again.
    @MainActor
    func testKunciOtomatisChoiceIsShownAgain() throws {
        let app = launch()
        app.buttons["list.settings"].tap()
        let row = app.buttons["settings.autoLock"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.label.contains("Setelah 1 menit"), row.label)
        row.tap()
        XCTAssertTrue(app.navigationBars["Kunci otomatis"].waitForExistence(timeout: 5))
        app.buttons["autoLock.fiveMinutes"].tap()
        XCTAssertTrue(app.buttons["autoLock.fiveMinutes"].isSelected)
        XCTAssertFalse(app.buttons["autoLock.oneMinute"].isSelected)
        screenshot("10 kunci otomatis")
        app.navigationBars["Kunci otomatis"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.label.contains("Setelah 5 menit"), row.label)

        app.navigationBars["Pengaturan"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["list.settings"].waitForExistence(timeout: 5))
        app.buttons["list.settings"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.label.contains("Setelah 5 menit"), "shown after reopening: \(row.label)")
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

    @MainActor
    func testLockAndOpen() throws {
        let app = launch()
        app.buttons["list.addSample"].tap()
        app.buttons["list.lock"].tap()
        XCTAssertTrue(app.buttons["lock.open"].waitForExistence(timeout: 5))
        XCTAssertFalse(rows(app).firstMatch.exists)
        screenshot("06 lock cover")
        app.buttons["lock.open"].tap()
        XCTAssertTrue(rows(app).firstMatch.waitForExistence(timeout: 5))
    }

    /// Every recovery screen that open() can lead to, with its text and way out.
    @MainActor
    func testRecoveryScreens() throws {
        let screens: [(arguments: [String], text: String, button: String)] = [
            (
                ["-SimpaninUITestOpenError", "keyMissing"],
                "Kunci vault tidak ditemukan. Ini bisa terjadi setelah memindahkan data ke HP baru.", "Mulai vault baru"
            ),
            (["-SimpaninUITestOpenError", "vaultUnreadable"], "Vault tidak bisa dibuka.", "Mulai vault baru"),
            (["-SimpaninUITestOpenError", "phoneLocked"], "Buka kunci HP, lalu coba lagi.", "Coba lagi"),
            (
                ["-SimpaninUITestOpenError", "otherStatus"],
                "Vault tidak bisa dibuka sekarang. Coba lagi nanti.", "Coba lagi"
            ),
            (
                ["-SimpaninUITestOpenError", "newerVersion"],
                "Versi Simpanin ini terlalu lama untuk vault ini. Perbarui app.", "Buka App Store"
            ),
            (
                ["-SimpaninUITestOpenError", "storageFull"],
                "Penyimpanan HP penuh. Kosongkan ruang untuk mulai memakai Simpanin.", "Coba lagi"
            ),
            (
                ["-SimpaninUITestPasscode", "notSet"],
                "Simpanin butuh passcode HP untuk mengunci dokumenmu.", "Buka Pengaturan"
            ),
        ]
        for (index, screen) in screens.enumerated() {
            let app = launch(screen.arguments)
            let message = app.staticTexts["recovery.message"]
            XCTAssertTrue(message.waitForExistence(timeout: 10), screen.text)
            XCTAssertEqual(message.label, screen.text)
            XCTAssertEqual(app.buttons["recovery.action"].label, screen.button)
            screenshot("07-\(index + 1) recovery \(screen.arguments[1])")
            app.terminate()
        }
    }

    @MainActor
    func testStartNewVaultNeedsTheTypedWords() throws {
        let app = launch(["-SimpaninUITestOpenError", "keyMissing", "-SimpaninUITestBrokenOldVault"])
        app.buttons["recovery.action"].tap()
        let confirm = app.buttons["startNew.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        XCTAssertFalse(confirm.isEnabled)
        let field = app.textFields["startNew.field"]
        field.tap()
        field.typeText("MULAI")
        XCTAssertFalse(confirm.isEnabled)
        field.typeText(" BARU")
        XCTAssertTrue(confirm.isEnabled)
        screenshot("08 mulai vault baru")
        confirm.tap()
        XCTAssertTrue(app.navigationBars["Dokumen"].waitForExistence(timeout: 10))

        // The vault failed before it was created, so nothing was moved aside. The broken folder
        // is shown, but can't be deleted yet.
        app.buttons["list.settings"].tap()
        app.buttons["settings.oldVaults"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["oldVaults.unreadable"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(identifier: "oldVaults.delete").count, 0)
        screenshot("09 data lama, folder tidak terbaca")
    }

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
        app.textFields["review.label"].typeText("Ibu")
        app.buttons["review.save"].tap()

        XCTAssertTrue(rows(app).firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(rows(app).count, 1)
        screenshot("21 the saved KTP in the list")
    }

    /// Sheets and full-screen covers sit above the root view, so the privacy cover must too: while the
    /// screen is recorded (or the app is in the switcher), the scan's fields can't be reached or seen.
    @MainActor
    func testTheCoverSitsAboveTheScanFlow() throws {
        let app = launch(["-SimpaninUITestScan", "-SimpaninUITestCaptureAfterScan"])
        openReview(app)
        let nik = app.textFields["review.field.nik"]
        expectation(for: NSPredicate(format: "isHittable == false"), evaluatedWith: nik)
        waitForExpectations(timeout: 10)
        screenshot("25 cover above the scan flow")
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
    }
}
