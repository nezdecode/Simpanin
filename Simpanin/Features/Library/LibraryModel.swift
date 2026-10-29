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

/// Where the documents hidden from the expiry banner are kept.
nonisolated protocol HiddenBannerStoring: Sendable {
    func load() throws -> HiddenBanner
    func save(_ hidden: HiddenBanner) throws
}

/// The live documents and Recently deleted, for the list screens. Shows only type and expiry;
/// fields and pages stay sealed until a document is opened.
@MainActor @Observable
final class LibraryModel {
    private(set) var documents: [Document] = []
    private(set) var deleted: [Document] = []
    /// The day the list and the banner read expiry against, worked out again when the app comes back.
    private(set) var today = CalendarDate.today
    /// The message for a failed save, if any.
    var saveError: RecoveryScreen?
    /// A short note on the list, like where a deleted document went.
    var notice: Toast?
    /// Loading failed. The screen shows that instead of an empty list, which would say the
    /// documents are gone.
    private(set) var loadFailed = false
    private let store: any DocumentStoring

    private(set) var hidden = HiddenBanner()
    private let hiddenStore: any HiddenBannerStoring
    /// The file has been read, or holds nothing to keep, so writing it loses nothing.
    private var hiddenLoaded = false
    /// The list in memory has hides the file doesn't, from a failed save or an unread file.
    private var hiddenUnsaved = false
    /// Ids with a hidden entry that the last reload found in neither list.
    private var missingLastReload: Set<DocumentID> = []

    /// The documents the banner may show: the user hasn't hidden them.
    var bannerDocuments: [Document] {
        documents.filter { !hidden.hides($0.id, expiry: $0.expiry, today: today) }
    }

    func refreshDay(at date: Date = .now, in calendar: Calendar = .current) {
        today = CalendarDate.day(of: date, in: calendar)
    }

    /// Whether the document screen offers "Tampilkan lagi": a live document within the banner's window
    /// that the user hid. A deleted one isn't in the banner either way.
    func offersShowInBanner(_ id: DocumentID) -> Bool {
        guard let document = documents.first(where: { $0.id == id }), let expiry = document.expiry else {
            return false
        }
        return ExpiryText.days(from: today, to: expiry) <= ExpiryText.soonWindow
            && hidden.hides(id, expiry: expiry, today: today)
    }

    /// Saved like a hide: a failed save keeps it in the banner and is tried again at the next reload.
    func showInBanner(_ id: DocumentID) {
        hidden.show(id)
        hiddenUnsaved = true
        saveHidden()
    }

    func hideFromBanner(_ document: Document) {
        guard let expiry = document.expiry else { return }
        hidden.hide(document.id, expiry: expiry, today: today)
        hiddenUnsaved = true
        saveHidden()
    }

    /// Reads the hidden list, unless memory holds hides a failed save left, and drops entries for documents
    /// two reloads in a row found in neither the list nor Baru dihapus: a restore or delete can land between
    /// those two reads. A deleted and restored document stays hidden.
    private func loadHidden() {
        if !hiddenLoaded || !hiddenUnsaved {
            do {
                let stored = try hiddenStore.load()
                hidden = hiddenUnsaved ? stored.merging(hidden) : stored
                hiddenLoaded = true
            } catch is DecodingError {
                // Not a hidden list at all: there's nothing in it to keep.
                Logger.library.error("Hidden banner list corrupt, replaced")
                hiddenLoaded = true
                hiddenUnsaved = true
            } catch {
                // Maybe readable later, so it isn't overwritten meanwhile.
                Logger.library.error("Hidden banner list unreadable: \(ErrorSummary.describe(error), privacy: .public)")
            }
        }
        let present = Set((documents + deleted).map(\.id))
        let missing = Set(hidden.entries.map(\.id)).subtracting(present)
        if hidden.prune(keeping: present.union(missing.subtracting(missingLastReload))) { hiddenUnsaved = true }
        missingLastReload = missing
        if hiddenUnsaved { saveHidden() }
    }

    private func saveHidden() {
        guard hiddenLoaded else { return }
        do {
            try hiddenStore.save(hidden)
            hiddenUnsaved = false
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

    /// True when it moved to Baru dihapus, so the document screen knows it may close.
    @discardableResult
    func delete(_ id: DocumentID) async -> Bool {
        let moved = await save { try await self.store.delete(id) }
        if moved { notice = Toast(title: "main.movedToDeleted") }
        return moved
    }

    func restore(_ id: DocumentID) async {
        await save { try await self.store.restore(id) }
    }

    #if DEBUG
        private var samples = 0

        /// "Tambah dokumen contoh": a synthetic document with generated pages.
        func addSample() async {
            samples += 1
            let sample = SampleDocument(number: samples, expiringSoon: UITestSetup.expiringSamples)
            await save {
                _ = try await self.store.createDocument(
                    type: sample.type, label: sample.label, expiry: sample.expiry, pinned: false, fields: sample.fields,
                    pages: sample.pages)
            }
        }
    #endif

    @discardableResult
    private func save(_ change: () async throws -> Void) async -> Bool {
        let saved: Bool
        do {
            try await change()
            saved = true
        } catch {
            // Only the kind of error; never an id, a field or a path.
            Logger.library.error("Save failed: \(ErrorSummary.describe(error), privacy: .public)")
            saveError = RecoveryMapping.screen(forSaveError: error)
            saved = false
        }
        await reload()
        return saved
    }
}
