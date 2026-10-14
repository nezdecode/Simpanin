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
final class Library {
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

/// "Data lama": old vaults moved aside by "Mulai vault baru". Deleting one also deletes its
/// Keychain item, through VaultCore.
@MainActor @Observable
final class OldVaultsModel {
    /// A folder VaultCore can't read. It can't be deleted safely yet, so it's only shown.
    struct UnreadableFolder: Equatable {
        let folder: URL
        let sizeInBytes: Int64
    }

    private(set) var vaults: [QuarantinedVault] = []
    private(set) var unreadable: [UnreadableFolder] = []
    private let store: any QuarantineStoring
    private let folder: URL

    init(store: any QuarantineStoring, folder: URL) {
        self.store = store
        self.folder = folder
    }

    nonisolated static func sizeText(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    nonisolated static func folderSize(_ folder: URL) -> Int64 {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        guard let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in files {
            guard let values = try? file.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else {
                continue
            }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }

    func reload() async {
        let listing = try? await store.quarantinedVaults(in: folder)
        vaults = listing?.vaults ?? []
        unreadable = (listing?.unreadableFolders ?? []).map {
            UnreadableFolder(folder: $0, sizeInBytes: Self.folderSize($0))
        }
    }

    func delete(_ vault: QuarantinedVault) async {
        try? await store.deleteQuarantinedVault(vault)
        await reload()
    }
}
