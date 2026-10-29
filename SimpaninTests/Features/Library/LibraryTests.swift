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
        let library = LibraryModel(store: store, hidden: FakeHiddenBanner())
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
        let library = LibraryModel(store: FakeDocuments(), hidden: FakeHiddenBanner())
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
        let library = LibraryModel(store: store, hidden: FakeHiddenBanner())
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
        let library = LibraryModel(store: store, hidden: FakeHiddenBanner())
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
        let library = LibraryModel(store: store, hidden: FakeHiddenBanner())
        await library.addSample()
        #expect(library.saveError == .storageFullOnSave)
        #expect(library.documents.isEmpty)
    }

    @Test func otherSaveFailuresSaySoButALockDoesNot() async {
        let store = FakeDocuments()
        let library = LibraryModel(store: store, hidden: FakeHiddenBanner())
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
        let library = LibraryModel(store: FakeDocuments(), hidden: FakeHiddenBanner())
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Makassar"))
        let morning = try #require(calendar.date(from: DateComponents(year: 2027, month: 3, day: 2, hour: 8)))
        library.refreshDay(at: morning, in: calendar)
        #expect(library.today == CalendarDate(year: 2027, month: 3, day: 2))
    }

    /// Hidden documents leave the banner, are kept across launches, and everything hidden means no banner.
    @Test func everythingHiddenMeansNoBanner() async throws {
        let store = FakeDocuments()
        let hidden = FakeHiddenBanner()
        let soon = CalendarDate.day(of: .now.addingTimeInterval(5 * 86_400), in: .current)
        _ = try await store.createDocument(
            type: .simC, label: nil, expiry: soon, pinned: false, fields: DocumentFields([:]), pages: [Data([1])])
        let library = LibraryModel(store: store, hidden: hidden)
        await library.reload()
        let document = try #require(library.bannerDocuments.first)
        library.hideFromBanner(document)
        #expect(library.bannerDocuments.isEmpty)
        #expect(library.documents.count == 1)
        let relaunched = LibraryModel(store: store, hidden: hidden)
        await relaunched.reload()
        #expect(relaunched.bannerDocuments.isEmpty)
    }

    /// A document purged for good, in neither the list nor Baru dihapus, leaves no hidden entry behind. It
    /// takes two reloads in a row, so a restore landing mid-reload can't drop it (see the next test).
    @Test func aPermanentlyDeletedDocumentLeavesNoHiddenEntry() async throws {
        let (store, hidden, library) = try await hiddenSoonDocument()
        let id = try #require(library.documents.first?.id)
        await library.delete(id)
        #expect(hidden.saved.entries.count == 1)
        await store.purge(id)
        await library.reload()
        #expect(hidden.saved.entries.count == 1)
        await library.reload()
        #expect(hidden.saved.entries.isEmpty)
    }

    @Test func aDocumentMissingFromOneReloadStaysHidden() async throws {
        let (store, hidden, library) = try await hiddenSoonDocument()
        let id = try #require(library.documents.first?.id)
        await store.missFromNextReload(id)
        await library.reload()
        await library.reload()
        #expect(hidden.saved.entries.map(\.id) == [id])
        #expect(library.bannerDocuments.isEmpty)
    }

    /// A relaunch whose list fails to load must not take the hidden list with it.
    @Test func nothingIsPrunedWhenAListFailsToLoad() async throws {
        let (store, hidden, _) = try await hiddenSoonDocument()
        await store.setBinFailure(.locked)
        let relaunched = LibraryModel(store: store, hidden: hidden)
        await relaunched.reload()
        await relaunched.reload()
        #expect(hidden.saved.entries.count == 1)
    }

    /// A list that can't be read is never overwritten, and hides made meanwhile join it once it can be.
    @Test func anUnreadableHiddenListIsNeverOverwritten() async throws {
        let (store, hidden, _) = try await hiddenSoonDocument()
        let before = hidden.saved
        let other = try await store.createDocument(
            type: .simA, label: nil, expiry: soonDay, pinned: false, fields: DocumentFields([:]), pages: [Data([1])])
        hidden.setLoadFailure(CocoaError(.fileReadUnknown))
        let relaunched = LibraryModel(store: store, hidden: hidden)
        await relaunched.reload()
        relaunched.hideFromBanner(try #require(relaunched.documents.first { $0.id == other }))
        #expect(hidden.saved == before)
        hidden.setLoadFailure(nil)
        await relaunched.reload()
        #expect(Set(hidden.saved.entries.map(\.id)).count == 2)
        #expect(relaunched.bannerDocuments.isEmpty)
    }

    /// A file that isn't a hidden list at all holds nothing to keep, so hiding replaces it.
    @Test func aCorruptHiddenListIsReplaced() async throws {
        let store = FakeDocuments()
        let hidden = FakeHiddenBanner()
        hidden.setLoadFailure(DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "not JSON")))
        _ = try await store.createDocument(
            type: .simC, label: nil, expiry: soonDay, pinned: false, fields: DocumentFields([:]), pages: [Data([1])])
        let library = LibraryModel(store: store, hidden: hidden)
        await library.reload()
        library.hideFromBanner(try #require(library.documents.first))
        #expect(hidden.saved.entries.count == 1)
    }

    /// A save that fails (a full disk) keeps the hide on screen and tries again at the next reload,
    /// instead of quietly bringing the document back.
    @Test func aFailedSaveKeepsTheHideAndRetries() async throws {
        let store = FakeDocuments()
        let hidden = FakeHiddenBanner()
        _ = try await store.createDocument(
            type: .simC, label: nil, expiry: soonDay, pinned: false, fields: DocumentFields([:]), pages: [Data([1])])
        let library = LibraryModel(store: store, hidden: hidden)
        await library.reload()
        hidden.setSaveFailure(CocoaError(.fileWriteOutOfSpace))
        library.hideFromBanner(try #require(library.documents.first))
        await library.reload()
        #expect(library.bannerDocuments.isEmpty)
        hidden.setSaveFailure(nil)
        await library.reload()
        #expect(hidden.saved.entries.count == 1)
    }

    var soonDay: CalendarDate { CalendarDate.day(of: .now.addingTimeInterval(5 * 86_400), in: .current) }

    /// One document expiring in five days, loaded and hidden from the banner.
    func hiddenSoonDocument() async throws -> (FakeDocuments, FakeHiddenBanner, LibraryModel) {
        let store = FakeDocuments()
        let hidden = FakeHiddenBanner()
        _ = try await store.createDocument(
            type: .simC, label: nil, expiry: soonDay, pinned: false, fields: DocumentFields([:]), pages: [Data([1])])
        let library = LibraryModel(store: store, hidden: hidden)
        await library.reload()
        library.hideFromBanner(try #require(library.documents.first))
        return (store, hidden, library)
    }
}
