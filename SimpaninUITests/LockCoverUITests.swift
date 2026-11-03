//
//  LockCoverUITests.swift
//  SimpaninUITests
//
//  Created by Inez Amanda on 18/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import XCTest

final class LockCoverUITests: UITestCase {
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

    /// Locked stays the lock screen while the screen is recorded, with Buka.
    @MainActor
    func testALockedVaultWhileRecordingShowsTheLockScreen() throws {
        let app = launch(["-SimpaninUITestRecordingAfterLock"])
        app.buttons["list.lock"].tap()
        XCTAssertTrue(app.buttons["lock.open"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["lock.subtitle"].label, "Terkunci. Dokumenmu terenkripsi di HP ini.")
        screenshot("06b lock cover while recording")
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
        // The user has already chosen, so the new vault opens straight away, without the welcome.
        XCTAssertFalse(app.staticTexts["welcome.title"].exists)

        // The vault failed before it was created, so nothing was moved aside. The broken folder
        // is shown, but can't be deleted yet.
        app.buttons["list.settings"].tap()
        app.buttons["settings.oldVaults"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["oldVaults.unreadable"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(identifier: "oldVaults.delete").count, 0)
        screenshot("09 data lama, folder tidak terbaca")
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
        // The vault is open, so the cover says why, never "Terkunci", and has no Buka.
        XCTAssertEqual(
            app.staticTexts["lock.subtitle"].label,
            "Disembunyikan selama layar direkam atau ditampilkan di layar lain.")
        XCTAssertFalse(app.buttons["lock.open"].exists)
        screenshot("25 cover above the scan flow")
        // When it stops, the review and its fields come back.
        XCTAssertTrue(app.textFields["review.field.nik"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["lock.title"].exists)
    }
}
