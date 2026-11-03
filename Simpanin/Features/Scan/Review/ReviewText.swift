//
//  ReviewText.swift
//  Simpanin
//
//  Created by Inez Amanda on 31/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import Parsers
import VaultCore

/// The texts "Periksa data" shows for its marks, refusals and the duplicate alert.
nonisolated enum ReviewText {
    /// The bar's button that replaces every page.
    static func rescan(_ source: ScanSource) -> LocalizedStringResource {
        source == .photos ? "review.pickAgain" : "review.rescan"
    }

    static func rescanConfirm(_ source: ScanSource) -> LocalizedStringResource {
        source == .photos ? "review.pickAgainConfirm" : "review.rescanConfirm"
    }

    /// Batal's question. Picked photos also say their originals stay in Photos.
    static func discardConfirm(_ source: ScanSource) -> LocalizedStringResource {
        source == .photos ? "review.discardPhotosConfirm" : "review.discardConfirm"
    }

    static func discardMessage(_ source: ScanSource) -> LocalizedStringResource? {
        source == .photos ? "review.originalsKept" : nil
    }

    /// Under the pages: importing never moves or deletes the photo it came from.
    static func pagesFootnote(_ source: ScanSource) -> LocalizedStringResource? {
        source == .photos ? "review.originalsStay" : nil
    }

    /// What shows under the type or the expiry: "Periksa lagi", with its reason when one is known.
    static func text(for note: ReviewModel.Note, numberKey: String?, onType: Bool = false) -> LocalizedStringResource {
        switch note {
        case .refusal(let problem): reason(for: problem)
        case .mark(nil): "review.checkAgain"
        case .mark(let reason?):
            "review.markWithReason \(String(localized: reasonText(reason, numberKey: numberKey, onType: onType)))"
        case .dateFromAnotherType: "review.markWithReason \(String(localized: "review.dateFromAnotherType"))"
        }
    }

    /// The text of a reason. Three name the number that holds the birth date: the NIK on a KTP, the number
    /// on a SIM. On the type, a lookalike is a SIM class read with a 1 for an I. The key is built as a plain
    /// string: interpolated, the code would become an argument.
    static func reasonText(_ reason: CheckReason, numberKey: String?, onType: Bool = false) -> LocalizedStringResource {
        var key = "review.reason." + reason.rawValue
        if onType && reason == .lookalike { key += ".type" }
        if [.noDateInNumber, .disagreesWithBirthDate, .sexDisagrees].contains(reason) {
            key += numberKey == FieldKey.simNumber ? ".simNumber" : ".nik"
        }
        return LocalizedStringResource(String.LocalizationValue(key))
    }

    /// "Kamu sudah punya SIM A dengan nomor ini.": a KTP has a NIK, a SIM a number.
    static func duplicateTitle(_ name: DocumentType) -> LocalizedStringResource {
        name == .ktp ? "review.duplicate.ktp" : "review.duplicate.sim \(String(localized: DocumentStyle.name(name)))"
    }

    static func reason(for problem: ReviewModel.FieldProblem) -> LocalizedStringResource {
        switch problem {
        case .notADate: "review.notADate"
        case .birthDateInFuture: "review.birthDateInFuture"
        case .nikLength: "review.nikLength"
        }
    }
}
