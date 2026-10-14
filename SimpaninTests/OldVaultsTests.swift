//
//  OldVaultsTests.swift
//  SimpaninTests
//
//  Created by Inez Amanda on 15/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import Testing

@testable import Simpanin
@testable import VaultCore

@MainActor
@Suite("Data lama")
struct OldVaultsTests {
    let folder = URL(filePath: "/Support/Quarantine", directoryHint: .isDirectory)

    func entry(_ name: String, size: Int64) -> QuarantinedVault {
        QuarantinedVault(vaultID: VaultID(), folder: folder.appending(path: name), sizeInBytes: size)
    }

    @Test func listsUnreadableFoldersToo() async {
        let store = FakeQuarantine()
        let old = entry("20261014-021200", size: 48_000_000)
        let broken = folder.appending(path: "20261002-031500")
        await store.setListing(QuarantineListing(vaults: [old], unreadableFolders: [broken]))
        let model = OldVaultsModel(store: store, folder: folder)
        await model.reload()
        #expect(model.vaults == [old])
        // The fake folder doesn't exist on disk, so its size reads as 0.
        #expect(model.unreadable == [OldVaultsModel.UnreadableFolder(url: broken, sizeInBytes: 0)])
    }

    @Test func folderSizeCountsEveryFile() throws {
        let base = FileManager.default.temporaryDirectory.appending(path: "Size-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: base) }
        try FileManager.default.createDirectory(at: base.appending(path: "pages"), withIntermediateDirectories: true)
        try Data(count: 3).write(to: base.appending(path: "vault.json"))
        try Data(count: 5).write(to: base.appending(path: "pages/one.enc"))
        #expect(OldVaultsModel.folderSize(base) == 8)
    }

    @Test func listsOldVaultsWithTheirSize() async {
        let store = FakeQuarantine()
        let old = entry("20261013-090000", size: 2_500_000)
        await store.setListing(QuarantineListing(vaults: [old], unreadableFolders: []))
        let model = OldVaultsModel(store: store, folder: folder)
        await model.reload()
        #expect(model.vaults == [old])
        #expect(!old.sizeInBytes.formatted(.byteCount(style: .file)).isEmpty)
    }

    @Test func deletingRemovesItThroughVaultCore() async {
        let store = FakeQuarantine()
        let old = entry("20261013-090000", size: 10)
        await store.setListing(QuarantineListing(vaults: [old], unreadableFolders: []))
        let model = OldVaultsModel(store: store, folder: folder)
        await model.reload()
        await model.delete(old)
        #expect(await store.deleted == [old])
        #expect(model.vaults.isEmpty)
    }

    // MARK: Data lama, named after when the vault was moved aside (folder names are UTC)

    let jakarta = TimeZone(identifier: "Asia/Jakarta")!

    @Test func oldVaultTitleAndDetail() throws {
        let moved = try #require(OldVaultText.movedAt(folderName: "20261014-021200"))
        #expect(String(localized: OldVaultText.title(moved, timeZone: jakarta)) == "Vault lama, 14 Okt 2026")
        #expect(
            String(localized: OldVaultText.detail(moved, sizeInBytes: 48_000_000, timeZone: jakarta))
                .hasSuffix("dipindahkan pukul 09.12"))
        // A second vault moved in the same second gets "-2"; the time still reads.
        #expect(OldVaultText.movedAt(folderName: "20261014-021200-2") == moved)
        #expect(OldVaultText.movedAt(folderName: "not-a-date") == nil)
        // An impossible date is not a date, rather than rolling over into the next year.
        #expect(OldVaultText.movedAt(folderName: "20261314-021200") == nil)
    }

    @Test func unreadableFolderShowsSizeAndDate() {
        let size = 12_000_000.formatted(.byteCount(style: .file))
        #expect(
            String(
                localized: OldVaultText.unreadableDetail(
                    folderName: "20261002-031500", sizeInBytes: 12_000_000, timeZone: jakarta))
                == "\(size) · 2 Okt 2026")
        #expect(
            String(localized: OldVaultText.unreadableDetail(folderName: "odd-name", sizeInBytes: 12_000_000))
                == size)
    }
}
