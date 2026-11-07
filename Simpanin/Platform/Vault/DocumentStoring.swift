//
//  DocumentStoring.swift
//  Simpanin
//
//  Created by Inez Amanda on 18/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import VaultCore

/// What the screens need from VaultStore's document calls, so tests can stand in for it.
nonisolated protocol DocumentStoring: Sendable {
    func documents() async throws -> [Document]
    func recentlyDeleted() async throws -> [Document]
    /// The duplicate check reads other saved documents through this; it must never ask for their pages.
    func fields(of id: DocumentID) async throws -> DocumentFields
    // swiftlint:disable:next function_parameter_count - mirrors VaultStore.createDocument
    func createDocument(
        type: DocumentType, label: String?, expiry: CalendarDate?, pinned: Bool, fields: DocumentFields,
        pages: [Data]
    ) async throws -> DocumentID
    /// Refuses a document in Baru dihapus with `documentDeleted`. The fields replace the stored ones whole.
    func editDocument(  // swiftlint:disable:this function_parameter_count - mirrors VaultStore.editDocument
        _ id: DocumentID, type: DocumentType, label: String?, expiry: CalendarDate?, pinned: Bool,
        fields: DocumentFields
    ) async throws
    func delete(_ id: DocumentID) async throws
    func restore(_ id: DocumentID) async throws
    func deletePermanently(_ id: DocumentID) async throws
}

extension VaultStore: DocumentStoring {}
