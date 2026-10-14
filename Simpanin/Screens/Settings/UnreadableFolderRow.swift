//
//  UnreadableFolderRow.swift
//  Simpanin
//
//  Created by Inez Amanda on 15/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

/// A folder in Data lama that VaultCore can't read. Shown, but it can't be deleted yet.
struct UnreadableFolderRow: View {
    let folder: OldVaultsModel.UnreadableFolder

    var body: some View {
        HStack(spacing: 12) {
            IconBadge(
                symbol: "exclamationmark.triangle", tint: Color(.onWarning), background: Color(.warning),
                outline: .rounded(8))
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
}
