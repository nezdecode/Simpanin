//
//  LibraryTests.swift
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
import UIKit

@testable import Simpanin
@testable import VaultCore

/// Stands in for VaultStore's document calls, with documents kept in memory.
actor FakeDocuments: DocumentStoring {
    private var live: [Document] = []
    private var bin: [Document] = []
    private(set) var created: [DocumentFields] = []
    private(set) var createdPages: [[Data]] = []
    private var failure: VaultError?

    func setFailure(_ failure: VaultError?) { self.failure = failure }

    func documents() async throws -> [Document] { live }
    func recentlyDeleted() async throws -> [Document] { bin }

    // swiftlint:disable:next function_parameter_count - mirrors VaultStore.createDocument
    func createDocument(
        type: DocumentType, label: String?, expiry: CalendarDate?, pinned: Bool, fields: DocumentFields,
        pages: [Data]
    ) async throws -> DocumentID {
        if let failure { throw failure }
        let id = DocumentID()
        created.append(fields)
        createdPages.append(pages)
        live.append(
            Document(
                id: id, type: type, createdAt: .now, updatedAt: .now, expiry: expiry, pinned: pinned,
                deletedAt: nil, pageIDs: pages.map { _ in PageID() }))
        return id
    }

    func delete(_ id: DocumentID) async throws {
        if let failure { throw failure }
        guard let index = live.firstIndex(where: { $0.id == id }) else { return }
        var document = live.remove(at: index)
        document.deletedAt = .now
        bin.append(document)
    }

    func restore(_ id: DocumentID) async throws {
        if let failure { throw failure }
        guard let index = bin.firstIndex(where: { $0.id == id }) else { return }
        var document = bin.remove(at: index)
        document.deletedAt = nil
        live.append(document)
    }
}

@MainActor
@Suite("Document list")
struct LibraryTests {
    @Test func sampleDocumentIsSyntheticWithOnePageImage() async throws {
        let store = FakeDocuments()
        let library = Library(store: store)
        await library.addSample()
        #expect(library.documents.count == 1)
        let fields = try #require(await store.created.first)
        let nik = try #require(fields.values["nik"])
        #expect(nik.hasPrefix("00") && nik.count == 16 && nik.allSatisfy(\.isNumber))
        let pages = try #require(await store.createdPages.first)
        #expect(pages.count == 1)
        #expect(UIImage(data: pages[0]) != nil)
    }

    @Test func deleteMovesToRecentlyDeletedAndRestoreBringsItBack() async throws {
        let library = Library(store: FakeDocuments())
        await library.addSample()
        let id = try #require(library.documents.first?.id)
        await library.delete(id)
        #expect(library.documents.isEmpty)
        #expect(library.deleted.map(\.id) == [id])
        await library.restore(id)
        #expect(library.documents.map(\.id) == [id])
        #expect(library.deleted.isEmpty)
    }

    @Test func aFullDiskOnASaveShowsItsScreen() async {
        let store = FakeDocuments()
        await store.setFailure(.storageFull)
        let library = Library(store: store)
        await library.addSample()
        #expect(library.saveError == .storageFullOnSave)
        #expect(library.documents.isEmpty)
    }

    @Test func otherSaveFailuresSaySoButALockDoesNot() async {
        let store = FakeDocuments()
        let library = Library(store: store)
        await store.setFailure(.fileUnavailable)
        await library.addSample()
        #expect(library.saveError == .saveFailed)
        library.saveError = nil
        await store.setFailure(.locked)
        await library.addSample()
        #expect(library.saveError == nil)
    }
}

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
        #expect(model.unreadable == [OldVaultsModel.UnreadableFolder(folder: broken, sizeInBytes: 0)])
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
        #expect(!OldVaultsModel.sizeText(old.sizeInBytes).isEmpty)
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
}

@MainActor
@Suite("Notices")
struct NoticeTests {
    @Test func aNoticeIsShownUntilDismissed() async {
        var report = OpenReport()
        report.newestChangeMayBeLost = true
        report.repairWaitingForSpace = true
        let lock = LockController(
            vault: FakeVault([.success(report)]), clock: FixedClock(), passcode: { .set },
            vaultExists: { true }, protectedDataAvailable: { true })
        await lock.unlock()
        #expect(lock.notices == [.newestChangeMayBeLost, .repairWaitingForSpace])
        lock.dismiss(.newestChangeMayBeLost)
        #expect(lock.notices == [.repairWaitingForSpace])
    }
}
