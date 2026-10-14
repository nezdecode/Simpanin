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

/// What the screens need from VaultStore's quarantine calls, so tests can stand in for it.
nonisolated protocol QuarantineStoring: Sendable {
    func quarantineVault(to quarantineDirectory: URL) async throws -> URL?
    func quarantinedVaults(in quarantineDirectory: URL) async throws -> QuarantineListing
    func deleteQuarantinedVault(_ vault: QuarantinedVault) async throws
}

extension VaultStore: QuarantineStoring {}

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

/// The texts of a "Data lama" entry. VaultCore names each folder after the moment it was moved
/// aside, in UTC (`yyyyMMdd-HHmmss`, plus "-2", "-3" when the name was taken).
nonisolated enum OldVaultText {
    static func movedAt(folderName: String) -> Date? {
        let stamp = String(folderName.prefix(15))
        guard stamp.count == 15 else { return nil }
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = .gmt
        parser.dateFormat = "yyyyMMdd-HHmmss"
        return parser.date(from: stamp)
    }

    static func title(_ movedAt: Date, timeZone: TimeZone = .current) -> LocalizedStringResource {
        "oldVaults.title \(IndonesianDate.dayMonthYear(movedAt, timeZone: timeZone))"
    }

    /// "12 MB · 2 Okt 2026", or only the size when the folder name has no date.
    static func unreadableDetail(
        folderName: String, sizeInBytes: Int64, timeZone: TimeZone = .current
    ) -> LocalizedStringResource {
        let size = OldVaultsModel.sizeText(sizeInBytes)
        guard let moved = movedAt(folderName: folderName) else { return "oldVaults.sizeOnly \(size)" }
        return "oldVaults.unreadableDetail \(size) \(IndonesianDate.dayMonthYear(moved, timeZone: timeZone))"
    }

    static func detail(_ movedAt: Date, sizeInBytes: Int64, timeZone: TimeZone = .current) -> LocalizedStringResource {
        let time = IndonesianDate.time(movedAt, timeZone: timeZone)
        return "oldVaults.detail \(OldVaultsModel.sizeText(sizeInBytes)) \(time)"
    }
}
