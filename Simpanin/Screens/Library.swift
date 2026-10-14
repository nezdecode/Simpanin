//
//  Library.swift
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

/// What the screens need from VaultStore's document calls, so tests can stand in for it.
nonisolated protocol DocumentStoring: Sendable {
    func documents() async throws -> [Document]
    func recentlyDeleted() async throws -> [Document]
    func createDocument(
        type: DocumentType, expiry: CalendarDate?, pinned: Bool, fields: DocumentFields, pages: [Data]
    ) async throws -> DocumentID
    func delete(_ id: DocumentID) async throws
    func restore(_ id: DocumentID) async throws
}

extension VaultStore: DocumentStoring {}

/// The live documents and Recently deleted, for the list screens. Shows only type and expiry;
/// fields and pages stay sealed until a document is opened.
@MainActor @Observable
final class Library {
    private(set) var documents: [Document] = []
    private(set) var deleted: [Document] = []
    /// Set when a save fails on a full disk. Other failures have no screen yet.
    var saveError: RecoveryScreen?
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
                    type: sample.type, expiry: sample.expiry, pinned: false, fields: sample.fields,
                    pages: [sample.page])
            }
        }
    #endif

    private func save(_ change: () async throws -> Void) async {
        do {
            try await change()
        } catch {
            saveError = RecoveryMapping.screen(forSaveError: error)
        }
        await reload()
    }
}

/// "Data lama": old vaults moved aside by "Mulai vault baru". Deleting one also deletes its
/// Keychain item, through VaultCore.
@MainActor @Observable
final class OldVaultsModel {
    private(set) var vaults: [QuarantinedVault] = []
    private let store: any QuarantineStoring
    private let folder: URL

    init(store: any QuarantineStoring, folder: URL) {
        self.store = store
        self.folder = folder
    }

    static func sizeText(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    func reload() async {
        vaults = (try? await store.quarantinedVaults(in: folder))?.vaults ?? []
    }

    func delete(_ vault: QuarantinedVault) async {
        try? await store.deleteQuarantinedVault(vault)
        await reload()
    }
}
