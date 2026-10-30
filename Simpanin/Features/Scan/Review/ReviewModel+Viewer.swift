//
//  ReviewModel+Viewer.swift
//  Simpanin
//
//  Created by Inez Amanda on 30/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import CoreGraphics
import Foundation
import VaultCore

/// What the page viewer shows over Periksa data.
extension ReviewModel {
    /// The strip's small copy, which stands in while the viewer's larger one is made.
    func thumbnail(_ index: Int) -> CGImage? {
        thumbnails.indices.contains(index) ? thumbnails[index].image : nil
    }

    /// A field under the enlarged page: what the form holds now, written as the card prints it.
    struct CheckedField: Equatable {
        let key: String
        /// Nil when empty; the bar says "Belum diisi".
        let value: String?
    }

    /// What's shown under the enlarged page, to compare with the card: the number always, first, then every
    /// other field that's marked or refused, in the form's order. The label isn't on the card.
    var checkedFields: [CheckedField] {
        let others = fieldKeys.filter { $0 != numberKey && note(for: $0) != nil }
        return ([numberKey].compactMap { $0 } + others).map { key in
            let text = values[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !text.isEmpty else { return CheckedField(key: key, value: nil) }
            // The NIK's 16 digits are printed together, a SIM number with dashes.
            let number = DocumentNumber(text)
            if key == FieldKey.nik { return CheckedField(key: key, value: number.digits) }
            if key == FieldKey.simNumber { return CheckedField(key: key, value: number.shown) }
            return CheckedField(key: key, value: text)
        }
    }

    /// A page for the viewer, redrawn each time no larger than the viewer takes; the model doesn't keep it.
    func viewerPage(_ index: Int) async -> CGImage? {
        guard pages.indices.contains(index) else { return nil }
        return await Self.enlarged(pages[index])
    }

    /// Off the main actor: redrawing a full-size scan takes long enough to hold up a swipe.
    @concurrent private static func enlarged(_ page: CGImage) async -> CGImage? {
        reducedPage(page, longSide: PageViewer.maxPixelSize)
    }
}
