//
//  LibraryModel.swift
//  Simpanin
//
//  Created by Inez Amanda on 14/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import Observation
import VaultCore
import os

/// What the screens need from VaultStore's document calls, so tests can stand in for it.
/// Where the documents hidden from the expiry banner are kept.
nonisolated protocol HiddenBannerStoring: Sendable {
    func load() throws -> HiddenBanner
    func save(_ hidden: HiddenBanner) throws
}

nonisolated protocol DocumentStoring: Sendable {
    func documents() async throws -> [Document]
    func recentlyDeleted() async throws -> [Document]
    // swiftlint:disable:next function_parameter_count - mirrors VaultStore.createDocument
    func createDocument(
        type: DocumentType, label: String?, expiry: CalendarDate?, pinned: Bool, fields: DocumentFields,
        pages: [Data]
    ) async throws -> DocumentID
    func delete(_ id: DocumentID) async throws
    func restore(_ id: DocumentID) async throws
}

extension VaultStore: DocumentStoring {}

/// The live documents and Recently deleted, for the list screens. Shows only type and expiry;
/// fields and pages stay sealed until a document is opened.
@MainActor @Observable
final class LibraryModel {
    private(set) var documents: [Document] = []
    private(set) var deleted: [Document] = []
    /// The day the list and the banner read expiry against, worked out again when the app comes back.
    private(set) var today = CalendarDate.today

    func refreshDay(at date: Date = .now, in calendar: Calendar = .current) {
        today = CalendarDate.day(of: date, in: calendar)
    }
    /// The message for a failed save, if any.
    var saveError: RecoveryScreen?
    /// Loading failed. The screen shows that instead of an empty list, which would say the
    /// documents are gone.
    private(set) var loadFailed = false
    private let store: any DocumentStoring

    private(set) var hidden = HiddenBanner()
    private let hiddenStore: any HiddenBannerStoring

    /// The documents the banner may show: the user hasn't hidden them.
    var bannerDocuments: [Document] {
        documents.filter { !hidden.hides($0.id, expiry: $0.expiry, today: today) }
    }

    func hideFromBanner(_ document: Document) {
        guard let expiry = document.expiry else { return }
        hidden.hide(document.id, expiry: expiry, today: today)
        saveHidden()
    }

    /// Loads the hidden list and drops entries for documents in neither the list nor Baru dihapus, so a
    /// deleted and restored one stays hidden. A list that can't be read only costs the banner its hiding.
    private func loadHidden() {
        do {
            hidden = try hiddenStore.load()
        } catch {
            Logger.library.error("Hidden banner list unreadable: \(ErrorSummary.describe(error), privacy: .public)")
        }
        if hidden.prune(keeping: Set((documents + deleted).map(\.id))) { saveHidden() }
    }

    private func saveHidden() {
        do {
            try hiddenStore.save(hidden)
        } catch {
            Logger.library.error("Hidden banner list not saved: \(ErrorSummary.describe(error), privacy: .public)")
        }
    }

    init(store: any DocumentStoring, hidden: any HiddenBannerStoring) {
        hiddenStore = hidden
        self.store = store
    }

    func reload() async {
        do {
            let live = try await store.documents()
            let bin = try await store.recentlyDeleted()
            documents = live
            deleted = bin
            loadFailed = false
            // Only with both lists read, so no hidden entry is pruned by a failed load.
            loadHidden()
        } catch {
            Logger.library.error("Load failed: \(ErrorSummary.describe(error), privacy: .public)")
            loadFailed = true
        }
    }

    func delete(_ id: DocumentID) async {
        await save { try await self.store.delete(id) }
    }

    func restore(_ id: DocumentID) async {
        await save { try await self.store.restore(id) }
    }

    #if DEBUG
        private var samples = 0

        /// "Tambah dokumen contoh": a synthetic document with one generated page.
        func addSample() async {
            samples += 1
            let sample = SampleDocument(number: samples)
            await save {
                _ = try await self.store.createDocument(
                    type: sample.type, label: sample.label, expiry: sample.expiry, pinned: false, fields: sample.fields,
                    pages: [sample.page])
            }
        }
    #endif

    private func save(_ change: () async throws -> Void) async {
        do {
            try await change()
        } catch {
            // Only the kind of error; never an id, a field or a path.
            Logger.library.error("Save failed: \(ErrorSummary.describe(error), privacy: .public)")
            saveError = RecoveryMapping.screen(forSaveError: error)
        }
        await reload()
    }
}
