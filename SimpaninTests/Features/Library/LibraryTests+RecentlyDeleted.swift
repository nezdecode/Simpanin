//
//  LibraryTests+RecentlyDeleted.swift
//  SimpaninTests
//
//  Created by Inez Amanda on 30/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import Testing

@testable import Simpanin
@testable import VaultCore

/// What a deleted document's screen asks of the list: Pulihkan and Hapus permanen.
extension LibraryTests {
    func deletedSample() async throws -> (FakeDocuments, LibraryModel, DocumentID) {
        let store = FakeDocuments()
        let library = LibraryModel(store: store, hidden: FakeHiddenBanner())
        await library.addSample()
        let id = try #require(library.documents.first?.id)
        await library.delete(id)
        return (store, library, id)
    }

    @Test func restoreSaysWhetherItWorked() async throws {
        let (_, library, id) = try await deletedSample()
        #expect(await library.restore(id))
        #expect(library.documents.map(\.id) == [id])
        #expect(library.deleted.isEmpty)
    }

    /// The deleted document's screen stays open, with the list's save alert.
    @Test func failedRestoreShowsTheAlert() async throws {
        let (store, library, id) = try await deletedSample()
        await store.setFailure(.fileUnavailable)
        #expect(await library.restore(id) == false)
        #expect(library.saveError == .saveFailed)
        #expect(library.deleted.map(\.id) == [id])
    }

    @Test func deletePermanentlyReloads() async throws {
        let (store, library, id) = try await deletedSample()
        #expect(await library.deletePermanently(id))
        #expect(library.deleted.isEmpty)
        #expect(library.documents.isEmpty)
        #expect(try await store.recentlyDeleted().isEmpty)
        #expect(library.saveError == nil)
    }

    /// At once, not after the two reloads that drop an entry whose document has gone.
    @Test func hapusPermanenRemovesTheHiddenEntry() async throws {
        let (_, hidden, library) = try await hiddenSoonDocument()
        let id = try #require(library.documents.first?.id)
        await library.delete(id)
        #expect(hidden.saved.entries.map(\.id) == [id])
        #expect(await library.deletePermanently(id))
        #expect(hidden.saved.entries.isEmpty)
        #expect(library.hidden.entries.isEmpty)
    }

    /// VaultStore purges a live document too, so the list refuses one.
    @Test func deletePermanentlyRefusesALiveDocument() async throws {
        let store = FakeDocuments()
        let library = LibraryModel(store: store, hidden: FakeHiddenBanner())
        await library.addSample()
        let id = try #require(library.documents.first?.id)
        #expect(await library.deletePermanently(id) == false)
        #expect(library.documents.map(\.id) == [id])
        #expect(try await store.documents().map(\.id) == [id])
    }

    @Test func failedDeletePermanentlyShowsTheAlertAndKeepsIt() async throws {
        let (store, hidden, library) = try await hiddenSoonDocument()
        let id = try #require(library.documents.first?.id)
        await library.delete(id)
        await store.setFailure(.fileUnavailable)
        #expect(await library.deletePermanently(id) == false)
        #expect(library.saveError == .saveFailed)
        #expect(library.deleted.map(\.id) == [id])
        #expect(hidden.saved.entries.map(\.id) == [id])
    }
}
