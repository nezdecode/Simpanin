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
