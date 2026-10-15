//
//  DocumentStyle.swift
//  Simpanin
//
//  Created by Inez Amanda on 14/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import DeveloperToolsSupport
import Foundation
import VaultCore

/// A type's name and tile colors. The colours only help tell types apart; the name is always
/// shown too.
nonisolated enum DocumentStyle {
    private static let nameKeys: [DocumentType: String] = [
        .ktp: "type.ktp", .sim: "type.sim", .simA: "type.simA", .simB1: "type.simB1", .simB2: "type.simB2",
        .simC: "type.simC", .simC1: "type.simC1", .simC2: "type.simC2", .simD: "type.simD", .simD1: "type.simD1",
        .simAUmum: "type.simAUmum", .simB1Umum: "type.simB1Umum", .simB2Umum: "type.simB2Umum",
        .passport: "type.passport", .stnk: "type.stnk", .kk: "type.kk", .npwp: "type.npwp", .bpjs: "type.bpjs",
    ]

    /// A type this build doesn't know, for example from a newer version, reads as "Lainnya".
    static func name(_ type: DocumentType) -> LocalizedStringResource {
        LocalizedStringResource(String.LocalizationValue(nameKeys[type] ?? "type.other"))
    }

    /// "NPWP · Kantor" for one-line rows. A blank label counts as none.
    static func name(_ type: DocumentType, label: String?) -> LocalizedStringResource {
        guard let label = shownLabel(label) else { return name(type) }
        return "type.withLabel \(String(localized: name(type))) \(label)"
    }

    static func shownLabel(_ label: String?) -> String? {
        guard let trimmed = label?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    /// Asset catalog colours, each with a light and a dark variant.
    @MainActor static func tileColors(_ type: DocumentType) -> (background: ColorResource, foreground: ColorResource) {
        if type.isSIM { return (.tileSIMBackground, .tileSIMForeground) }
        return switch type {
        case .ktp: (.tileKTPBackground, .tileKTPForeground)
        case .passport: (.tilePassportBackground, .tilePassportForeground)
        case .stnk: (.tileSTNKBackground, .tileSTNKForeground)
        case .kk: (.tileKKBackground, .tileKKForeground)
        case .npwp: (.tileNPWPBackground, .tileNPWPForeground)
        case .bpjs: (.tileBPJSBackground, .tileBPJSForeground)
        default: (.tileOtherBackground, .tileOtherForeground)
        }
    }
}
