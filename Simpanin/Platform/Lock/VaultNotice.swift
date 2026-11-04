//
//  VaultNotice.swift
//  Simpanin
//
//  Created by Inez Amanda on 14/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

/// A one-time notice after the vault opened.
nonisolated enum VaultNotice: Hashable, Sendable, CaseIterable {
    /// "Perubahan terakhir mungkin belum tersimpan. Periksa dokumen yang baru kamu ubah."
    case newestChangeMayBeLost
    /// "Vault dipulihkan dari gambar. ..."
    case recoveredFromPages
    /// The banner that doesn't block: a full disk held back a repair or purge.
    case repairWaitingForSpace
    /// "Pindaian yang belum disimpan dibuang karena Simpanin terkunci. ..."
    case scanDropped
    /// "Dokumen dari Foto belum disimpan, jadi dibatalkan karena Simpanin terkunci. ..."
    case photosDropped
    /// "Berbagi dihentikan karena Simpanin terkunci. ..."
    case shareStopped
}

extension VaultNotice {
    nonisolated var message: LocalizedStringResource {
        switch self {
        case .newestChangeMayBeLost: LocalizedStringResource("notice.newestChangeMayBeLost")
        case .recoveredFromPages: LocalizedStringResource("notice.recoveredFromPages")
        case .repairWaitingForSpace: LocalizedStringResource("notice.repairWaitingForSpace")
        case .scanDropped: LocalizedStringResource("notice.scanDropped")
        case .photosDropped: LocalizedStringResource("notice.photosDropped")
        case .shareStopped: LocalizedStringResource("notice.shareStopped")
        }
    }
}
