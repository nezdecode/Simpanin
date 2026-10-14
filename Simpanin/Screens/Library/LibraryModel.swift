//
//  LibraryModel.swift
//  Simpanin
//
//  Created by Inez Amanda on 15/10/26.
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
    /// The message for a failed save, if any.
    var saveError: RecoveryScreen?
    private let logger = Logger(subsystem: "com.inez.Simpanin", category: "library")
    private let store: any DocumentStoring

    init(store: any DocumentStoring) {
        self.store = store
    }

    func reload() async {
        documents = (try? await store.documents()) ?? []
        deleted = (try? await store.recentlyDeleted()) ?? []
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
            logger.error("Save failed: \(ErrorSummary.describe(error), privacy: .public)")
            saveError = RecoveryMapping.screen(forSaveError: error)
        }
        await reload()
    }
}
