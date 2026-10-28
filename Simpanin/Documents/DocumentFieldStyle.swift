//
//  DocumentFieldStyle.swift
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

/// Which fields a type has and what they're called, for every screen that shows them.
nonisolated enum DocumentFieldStyle {
    /// Only the types a parser reads have fields to check; the others have none yet.
    static func keys(for type: DocumentType) -> [String] {
        if type == .ktp { return [FieldKey.nik, FieldKey.name, FieldKey.birthDate] }
        if type.isSIM { return [FieldKey.simNumber, FieldKey.name, FieldKey.birthDate] }
        return []
    }

    /// Any other key reads as the name; only keys from `keys(for:)` are ever shown.
    static func title(for key: String) -> LocalizedStringResource {
        switch key {
        case FieldKey.nik: "field.nik"
        case FieldKey.simNumber: "field.simNumber"
        case FieldKey.birthDate: "field.birthDate"
        default: "field.name"
        }
    }

    /// An STNK's date is its yearly tax; every other type's is its validity.
    static func validityTitle(for type: DocumentType) -> LocalizedStringResource {
        type == .stnk ? "review.taxValidUntil" : "review.validUntil"
    }
}
