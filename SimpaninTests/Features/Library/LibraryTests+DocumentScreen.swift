//
//  LibraryTests+DocumentScreen.swift
//  SimpaninTests
//
//  Created by Inez Amanda on 28/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import Testing

@testable import Simpanin
@testable import VaultCore

/// What the document screen asks of the list: "Tampilkan lagi" and Hapus.
extension LibraryTests {
    /// Offered only for a live document the banner would show but the user hid.
    @Test func bannerUnhideIsOnTheLiveScreen() async throws {
        let (store, _, library) = try await hiddenSoonDocument()
        let id = try #require(library.documents.first?.id)
        #expect(library.offersShowInBanner(id))
        let shown = try await store.createDocument(
            type: .simA, label: nil, expiry: soonDay, pinned: false, fields: DocumentFields([:]), pages: [Data([1])])
        let far = CalendarDate.day(of: .now.addingTimeInterval(200 * 86_400), in: .current)
        let farAway = try await store.createDocument(
            type: .simA, label: nil, expiry: far, pinned: false, fields: DocumentFields([:]), pages: [Data([1])])
        await library.reload()
        library.hideFromBanner(try #require(library.documents.first { $0.id == farAway }))
        #expect(!library.offersShowInBanner(shown))
        #expect(!library.offersShowInBanner(farAway))
        await library.delete(id)
        #expect(!library.offersShowInBanner(id))
    }

    @Test func showInBannerBringsItBack() async throws {
        let (_, hidden, library) = try await hiddenSoonDocument()
        let id = try #require(library.documents.first?.id)
        library.showInBanner(id)
        #expect(library.bannerDocuments.map(\.id) == [id])
        #expect(!library.offersShowInBanner(id))
        #expect(hidden.saved.entries.isEmpty)
    }

    /// Like a failed hide: the document stays in the banner, and the save is tried again at the next reload.
    @Test func aFailedUnhideSaveKeepsItAndRetries() async throws {
        let (_, hidden, library) = try await hiddenSoonDocument()
        let id = try #require(library.documents.first?.id)
        hidden.setSaveFailure(CocoaError(.fileWriteOutOfSpace))
        library.showInBanner(id)
        await library.reload()
        #expect(library.bannerDocuments.map(\.id) == [id])
        #expect(hidden.saved.entries.map(\.id) == [id])
        hidden.setSaveFailure(nil)
        await library.reload()
        #expect(hidden.saved.entries.isEmpty)
        #expect(library.bannerDocuments.map(\.id) == [id])
    }

    @Test func deleteSaysWhereItWent() async throws {
        let library = LibraryModel(store: FakeDocuments(), hidden: FakeHiddenBanner())
        await library.addSample()
        let id = try #require(library.documents.first?.id)
        #expect(await library.delete(id))
        #expect(library.notice.map { String(localized: $0) } == "Dipindahkan ke Baru dihapus.")
        #expect(library.deleted.map(\.id) == [id])
    }

    /// The document screen stays open, and the list says nothing moved.
    @Test func failedDeleteShowsTheAlertAndNoNote() async throws {
        let store = FakeDocuments()
        let library = LibraryModel(store: store, hidden: FakeHiddenBanner())
        await library.addSample()
        let id = try #require(library.documents.first?.id)
        await store.setFailure(.fileUnavailable)
        #expect(await library.delete(id) == false)
        #expect(library.saveError == .saveFailed)
        #expect(library.notice == nil)
        #expect(library.documents.map(\.id) == [id])
    }
}
