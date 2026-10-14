//
//  OldVaultsModel.swift
//  Simpanin
//
//  Created by Inez Amanda on 15/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Observation
import SwiftUI
import VaultCore

/// "Data lama": old vaults moved aside by "Mulai vault baru". Deleting one also deletes its
/// Keychain item, through VaultCore.
@MainActor @Observable
final class OldVaultsModel {
    /// A folder VaultCore can't read. It can't be deleted safely yet, so it's only shown.
    struct UnreadableFolder: Equatable {
        let url: URL
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
            UnreadableFolder(url: $0, sizeInBytes: Self.folderSize($0))
        }
    }

    func delete(_ vault: QuarantinedVault) async {
        try? await store.deleteQuarantinedVault(vault)
        await reload()
    }
}
