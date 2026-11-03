//
//  RecoveryContentTests.swift
//  SimpaninTests
//
//  Created by Inez Amanda on 14/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import Synchronization
import Testing

@testable import Simpanin
@testable import VaultCore

/// The texts and ways out of the recovery table, word for word.
@Suite("Recovery screens: texts and actions")
struct RecoveryContentTests {
    static let texts: [(RecoveryScreen, String)] = [
        (.keyMissing, "Kunci vault tidak ditemukan. Ini bisa terjadi setelah memindahkan data ke HP baru."),
        (.vaultUnreadable, "Vault tidak bisa dibuka."),
        (.passcodeNeeded, "Simpanin butuh passcode HP untuk mengunci dokumenmu."),
        (.passcodeTurnedOff, "Pasang passcode lagi untuk membuka vault."),
        (.unlockPhoneAndRetry, "Buka kunci HP, lalu coba lagi."),
        (.cannotOpenNow, "Vault tidak bisa dibuka sekarang. Coba lagi nanti."),
        (.updateApp, "Versi Simpanin ini terlalu lama untuk vault ini. Perbarui app."),
        (.storageFullOnOpen, "Penyimpanan HP penuh. Kosongkan ruang untuk mulai memakai Simpanin."),
        (.storageFullOnSave, "Penyimpanan HP penuh. Perubahan belum tersimpan, data lama aman."),
        (.saveFailed, "Perubahan belum tersimpan. Coba lagi."),
    ]

    @Test(arguments: texts)
    func screenText(_ screen: RecoveryScreen, _ text: String) {
        #expect(String(localized: RecoveryContent(screen).message) == text)
    }

    @Test func noticeTexts() {
        #expect(
            String(localized: VaultNotice.newestChangeMayBeLost.message)
                == "Perubahan terakhir mungkin belum tersimpan. Periksa dokumen yang baru kamu ubah.")
        #expect(
            String(localized: VaultNotice.recoveredFromPages.message)
                == "Vault dipulihkan dari gambar. Nomor, nama, dan tanggal perlu diisi ulang, "
                + "dan dokumen yang sudah dihapus mungkin muncul kembali.")
        #expect(
            String(localized: VaultNotice.repairWaitingForSpace.message)
                == "Penyimpanan HP hampir penuh. Beberapa perbaikan akan disimpan setelah ada ruang.")
        #expect(
            String(localized: VaultNotice.scanDropped.message)
                == "Pindaian yang belum disimpan dibuang karena Simpanin terkunci. Pindai lagi kalau perlu.")
        #expect(
            String(localized: VaultNotice.photosDropped.message)
                == "Dokumen dari Foto belum disimpan, jadi dibatalkan karena Simpanin terkunci. "
                + "Foto aslinya tetap ada di app Foto.")
    }

    @Test func buttonTexts() {
        #expect(String(localized: ScreenText.open) == "Buka")
        #expect(String(localized: ScreenText.startNewVault) == "Mulai vault baru")
    }

    /// The design's "couldn't load" state, word for word.
    @Test func loadFailedTexts() {
        #expect(String(localized: LoadFailedView.title) == "Dokumen tidak bisa dimuat sekarang.")
        #expect(
            String(localized: LoadFailedView.message) == "Simpanin tidak mengubah apa pun. Coba lagi sebentar lagi.")
        #expect(String(localized: ScreenText.retry) == "Coba lagi")
    }

    /// The "Way out" column.
    @Test func tonesFollowWhatTheUserHasToDo() {
        #expect(RecoveryContent(.passcodeNeeded).tone == .needsAction)
        #expect(RecoveryContent(.passcodeTurnedOff).tone == .needsAction)
        #expect(RecoveryContent(.unlockPhoneAndRetry).tone == .temporary)
        #expect(RecoveryContent(.cannotOpenNow).tone == .temporary)
        #expect(RecoveryContent(.storageFullOnOpen).tone == .temporary)
        #expect(RecoveryContent(.keyMissing).tone == .decision)
        #expect(RecoveryContent(.vaultUnreadable).tone == .decision)
        #expect(RecoveryContent(.updateApp).tone == .update)
        let symbols: [RecoveryContent.Tone: String] = [
            .needsAction: "lock", .temporary: "arrow.clockwise", .decision: "questionmark", .update: "arrow.up",
        ]
        for (tone, symbol) in symbols { #expect(tone.systemImage == symbol) }
    }

    @Test func waysOut() {
        #expect(RecoveryContent(.keyMissing).action == .startNewVault)
        #expect(RecoveryContent(.vaultUnreadable).action == .startNewVault)
        #expect(RecoveryContent(.passcodeNeeded).action == .openSettings)
        #expect(RecoveryContent(.passcodeTurnedOff).action == .openSettings)
        #expect(RecoveryContent(.unlockPhoneAndRetry).action == .retry)
        #expect(RecoveryContent(.cannotOpenNow).action == .retry)
        #expect(RecoveryContent(.storageFullOnOpen).action == .retry)
        #expect(RecoveryContent(.updateApp).action == .openAppStore)
        #expect(RecoveryContent(.storageFullOnSave).action == .dismiss)
        #expect(RecoveryContent(.saveFailed).action == .dismiss)
    }
}
