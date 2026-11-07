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

/// The texts only "Periksa data" shows: those that depend on where its pages came from. The form's own
/// texts are in `FormText`.
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
}
