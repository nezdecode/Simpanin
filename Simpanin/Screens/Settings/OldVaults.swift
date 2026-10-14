//
//  OldVaults.swift
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
        var style = Date.FormatStyle(locale: Locale(identifier: "id_ID")).day().month(.abbreviated).year()
        style.timeZone = timeZone
        return "oldVaults.title \(movedAt.formatted(style))"
    }

    /// "12 MB · 2 Okt 2026", or only the size when the folder name has no date.
    static func unreadableDetail(
        folderName: String, sizeInBytes: Int64, timeZone: TimeZone = .current
    ) -> LocalizedStringResource {
        let size = OldVaultsModel.sizeText(sizeInBytes)
        guard let moved = movedAt(folderName: folderName) else { return "oldVaults.sizeOnly \(size)" }
        var style = Date.FormatStyle(locale: Locale(identifier: "id_ID")).day().month(.abbreviated).year()
        style.timeZone = timeZone
        return "oldVaults.unreadableDetail \(size) \(moved.formatted(style))"
    }

    static func detail(_ movedAt: Date, sizeInBytes: Int64, timeZone: TimeZone = .current) -> LocalizedStringResource {
        let time = DateFormatter()
        time.locale = Locale(identifier: "id_ID")
        time.timeZone = timeZone
        time.dateFormat = "HH.mm"
        return "oldVaults.detail \(OldVaultsModel.sizeText(sizeInBytes)) \(time.string(from: movedAt))"
    }
}

/// "Data lama": old vaults moved aside by "Mulai vault baru". Deleting one asks first, because it
/// also deletes the old vault's Keychain item.
struct OldVaultsView: View {
    @State var model: OldVaultsModel
    @State private var pendingDelete: QuarantinedVault?

    var body: some View {
        List {
            Section {
                if model.vaults.isEmpty && model.unreadable.isEmpty {
                    Text("oldVaults.empty").foregroundStyle(.secondary)
                }
                ForEach(model.vaults, id: \.folder) { old in
                    HStack(spacing: 12) {
                        OldVaultIcon(symbol: "archivebox", tint: .secondary, background: Color(.systemGray5))
                        VStack(alignment: .leading, spacing: 2) {
                            if let moved = OldVaultText.movedAt(folderName: old.folder.lastPathComponent) {
                                Text(OldVaultText.title(moved))
                                Text(OldVaultText.detail(moved, sizeInBytes: old.sizeInBytes))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text(verbatim: OldVaultsModel.sizeText(old.sizeInBytes))
                            }
                        }
                        Spacer(minLength: 0)
                        Button(role: .destructive) {
                            pendingDelete = old
                        } label: {
                            Text("button.delete")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(Color("Destructive"))
                        .accessibilityIdentifier("oldVaults.delete")
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            pendingDelete = old
                        } label: {
                            Text("button.delete")
                        }
                    }
                }
                ForEach(model.unreadable, id: \.folder) { folder in
                    HStack(spacing: 12) {
                        OldVaultIcon(
                            symbol: "exclamationmark.triangle", tint: Color("OnWarning"), background: Color("Warning"))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("oldVaults.unreadableTitle")
                            Text(
                                OldVaultText.unreadableDetail(
                                    folderName: folder.folder.lastPathComponent, sizeInBytes: folder.sizeInBytes)
                            )
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("oldVaults.unreadable")
                }
            } header: {
                Text("oldVaults.explanation").textCase(nil)
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    if !model.vaults.isEmpty { Text("oldVaults.footer") }
                    if !model.unreadable.isEmpty { Text("oldVaults.unreadableFooter") }
                }
            }
        }
        .navigationTitle(Text("settings.oldVaults"))
        .task { await model.reload() }
        .confirmationDialog(
            Text("oldVaults.deleteConfirm"),
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                if let old = pendingDelete { Task { await model.delete(old) } }
                pendingDelete = nil
            } label: {
                Text("button.deleteForever")
            }
        } message: {
            Text("oldVaults.deleteMessage")
        }
    }
}

/// The rounded square in front of a Data lama row.
struct OldVaultIcon: View {
    let symbol: String
    let tint: Color
    let background: Color

    var body: some View {
        Image(systemName: symbol)
            .foregroundStyle(tint)
            .frame(width: 36, height: 36)
            .background(background, in: .rect(cornerRadius: 8))
            .accessibilityHidden(true)
    }
}
