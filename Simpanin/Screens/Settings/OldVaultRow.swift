//
//  OldVaultRow.swift
//  Simpanin
//
//  Created by Inez Amanda on 15/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI
import VaultCore

/// An old vault in Data lama, with when it was moved aside, its size and a visible Hapus.
struct OldVaultRow: View {
    let vault: QuarantinedVault
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            IconBadge(
                symbol: "archivebox", tint: .secondary, background: Color(.systemGray5),
                outline: .rounded(8))
            VStack(alignment: .leading, spacing: 2) {
                if let moved = OldVaultText.movedAt(folderName: vault.folder.lastPathComponent) {
                    Text(OldVaultText.title(moved))
                    Text(OldVaultText.detail(moved, sizeInBytes: vault.sizeInBytes))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text(verbatim: OldVaultsModel.sizeText(vault.sizeInBytes))
                }
            }
            Spacer(minLength: 0)
            Button(role: .destructive) {
                onDelete()
            } label: {
                Text("button.delete")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Color(.destructive))
            .accessibilityIdentifier("oldVaults.delete")
        }
        .swipeActions {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Text("button.delete")
            }
        }
    }
}
