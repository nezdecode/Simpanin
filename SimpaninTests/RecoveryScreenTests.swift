//
//  RecoveryScreenTests.swift
//  SimpaninTests
//
//  Created by Inez Amanda on 15/10/26.
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

/// The texts and ways out of the design doc's recovery table, word for word.
@Suite("Recovery screens: texts and actions")
struct RecoveryScreenTests {
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
    }

    @Test func buttonTexts() {
        #expect(String(localized: ScreenText.open) == "Buka")
        #expect(String(localized: ScreenText.startNewVault) == "Mulai vault baru")
    }

    /// The "Way out" column.
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

/// Stands in for VaultStore's quarantine calls.
actor FakeQuarantine: QuarantineStoring {
    private(set) var quarantinedTo: [URL] = []
    private(set) var deleted: [QuarantinedVault] = []
    var listing = QuarantineListing(vaults: [], unreadableFolders: [])
    var failure: VaultError?

    func setListing(_ listing: QuarantineListing) { self.listing = listing }
    func setFailure(_ failure: VaultError?) { self.failure = failure }

    func quarantineVault(to quarantineDirectory: URL) async throws -> URL? {
        if let failure { throw failure }
        quarantinedTo.append(quarantineDirectory)
        return quarantineDirectory.appending(path: "20261015-010000")
    }

    func quarantinedVaults(in quarantineDirectory: URL) async throws -> QuarantineListing { listing }

    func deleteQuarantinedVault(_ vault: QuarantinedVault) async throws {
        if let failure { throw failure }
        deleted.append(vault)
        listing.vaults.removeAll { $0 == vault }
    }
}

@MainActor
@Suite("Mulai vault baru")
struct StartNewVaultTests {
    let quarantineFolder = URL(filePath: "/Support/Quarantine", directoryHint: .isDirectory)

    func makeLock(_ vault: FakeVault) -> LockController {
        LockController(
            vault: vault, clock: FixedClock(), passcode: { .set }, vaultExists: { true },
            protectedDataAvailable: { true })
    }

    @Test(arguments: ["MULAI BARU", "mulai baru", "  Mulai Baru "])
    func typedConfirmationMatches(_ text: String) {
        #expect(StartNewVaultModel.matches(text))
    }

    @Test(arguments: ["", "MULAI", "mulaibaru", "MULAI BARU!", "ya"])
    func otherTextDoesNotMatch(_ text: String) {
        #expect(!StartNewVaultModel.matches(text))
    }

    @Test func confirmingQuarantinesThenOpens() async {
        let quarantine = FakeQuarantine()
        let vault = FakeVault([.failure(.vaultKeyMissing), .success(OpenReport())])
        let lock = makeLock(vault)
        await lock.unlock()
        #expect(lock.state == .recovery(.keyMissing))

        let model = StartNewVaultModel(store: quarantine, quarantineFolder: quarantineFolder, lock: lock)
        model.typed = "MULAI BARU"
        await model.confirm()
        #expect(await quarantine.quarantinedTo == [quarantineFolder])
        #expect(lock.state == .unlocked)
    }

    @Test func nothingHappensWithoutTheWord() async {
        let quarantine = FakeQuarantine()
        let vault = FakeVault([.failure(.vaultUnreadable)])
        let lock = makeLock(vault)
        await lock.unlock()
        let model = StartNewVaultModel(store: quarantine, quarantineFolder: quarantineFolder, lock: lock)
        model.typed = "mulai"
        await model.confirm()
        #expect(await quarantine.quarantinedTo.isEmpty)
        #expect(await vault.openCount == 1)
    }

    @Test func aFailedMoveKeepsTheScreenAndSaysSo() async {
        let quarantine = FakeQuarantine()
        await quarantine.setFailure(.fileUnavailable)
        let vault = FakeVault([.failure(.vaultUnreadable)])
        let lock = makeLock(vault)
        await lock.unlock()
        let model = StartNewVaultModel(store: quarantine, quarantineFolder: quarantineFolder, lock: lock)
        model.typed = "MULAI BARU"
        await model.confirm()
        #expect(model.failed)
        #expect(lock.state == .recovery(.vaultUnreadable))
        #expect(await vault.openCount == 1)
    }
}
