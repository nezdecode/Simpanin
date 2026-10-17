//
//  LibraryTests.swift
//  SimpaninTests
//
//  Created by Inez Amanda on 14/10/26.
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
        let library = LibraryModel(store: store)
        await library.addSample()
        #expect(library.documents.count == 1)
        let fields = try #require(await store.created.first)
        let nik = try #require(fields.values[FieldKey.nik])
        #expect(nik.hasPrefix("00") && nik.count == 16 && nik.allSatisfy(\.isNumber))
        let pages = try #require(await store.createdPages.first)
        #expect(pages.count == 1)
        #expect(UIImage(data: pages[0]) != nil)
    }

    @Test func deleteMovesToRecentlyDeletedAndRestoreBringsItBack() async throws {
        let library = LibraryModel(store: FakeDocuments())
        await library.addSample()
        let id = try #require(library.documents.first?.id)
        await library.delete(id)
        #expect(library.documents.isEmpty)
        #expect(library.deleted.map(\.id) == [id])
        await library.restore(id)
        #expect(library.documents.map(\.id) == [id])
        #expect(library.deleted.isEmpty)
    }

    /// A failed load must never look like an empty vault.
    @Test func aFailedLoadSaysSoAndKeepsTheList() async throws {
        let store = FakeDocuments()
        let library = LibraryModel(store: store)
        await library.addSample()
        #expect(library.documents.count == 1)
        #expect(!library.loadFailed)

        await store.setLoadFailure(.locked)
        await library.reload()
        #expect(library.loadFailed)
        #expect(library.documents.count == 1)

        await store.setLoadFailure(nil)
        await library.reload()
        #expect(!library.loadFailed)
    }

    /// If only the bin fails, the list still counts as failed and keeps both halves, so it never
    /// shows fresh documents next to a bin that pretends to be empty.
    @Test func aHalfFailedLoadKeepsBothAndRetryRefreshes() async throws {
        let store = FakeDocuments()
        let library = LibraryModel(store: store)
        await library.addSample()
        await library.addSample()
        let first = try #require(library.documents.first)
        await library.delete(first.id)
        #expect(library.documents.count == 1)
        #expect(library.deleted.count == 1)

        await store.setBinFailure(.locked)
        await library.addSample()
        #expect(library.loadFailed)
        #expect(library.documents.count == 1)
        #expect(library.deleted.count == 1)

        await store.setBinFailure(nil)
        await library.reload()
        #expect(!library.loadFailed)
        #expect(library.documents.count == 2)
        #expect(library.deleted.count == 1)
    }

    @Test func aFullDiskOnASaveShowsItsScreen() async {
        let store = FakeDocuments()
        await store.setFailure(.storageFull)
        let library = LibraryModel(store: store)
        await library.addSample()
        #expect(library.saveError == .storageFullOnSave)
        #expect(library.documents.isEmpty)
    }

    @Test func otherSaveFailuresSaySoButALockDoesNot() async {
        let store = FakeDocuments()
        let library = LibraryModel(store: store)
        await store.setFailure(.fileUnavailable)
        await library.addSample()
        #expect(library.saveError == .saveFailed)
        library.saveError = nil
        await store.setFailure(.locked)
        await library.addSample()
        #expect(library.saveError == nil)
    }

    /// The banner's "today" is worked out again when the app comes back, not only at launch.
    @Test func theDayIsRecalculatedWhenTheAppReturns() throws {
        let library = LibraryModel(store: FakeDocuments())
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Makassar"))
        let morning = try #require(calendar.date(from: DateComponents(year: 2027, month: 3, day: 2, hour: 8)))
        library.refreshDay(at: morning, in: calendar)
        #expect(library.today == CalendarDate(year: 2027, month: 3, day: 2))
    }
}
