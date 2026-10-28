//
//  PageReading.swift
//  Simpanin
//
//  Created by Inez Amanda on 28/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import VaultCore

/// Reads a saved document's pages, for the document screen only: the duplicate check gets
/// `DocumentStoring`, which has no page call. One page at a time, so one that can't be opened
/// doesn't hide the others. The decrypted bytes, as VaultCore's `Page` can't be built outside it.
nonisolated protocol PageReading: Sendable {
    func pageData(_ pageID: PageID, of id: DocumentID) async throws -> Data
}

extension VaultStore: PageReading {
    func pageData(_ pageID: PageID, of id: DocumentID) throws -> Data { try page(pageID, of: id).data }
}
