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
import Parsers
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
        let title: LocalizedStringResource
        /// Nil when empty; the bar says "Belum diisi".
        let value: String?
        /// Read digit by digit, in a fixed-width font.
        let isNumber: Bool

        /// Berlaku sampai isn't a field, so it has a key of its own here.
        static let expiryKey = "expiry"
    }

    /// What's shown under the enlarged page, to compare with the card: the number always, first, then every
    /// other field that's marked or refused, in the form's order, and last Berlaku sampai when it's marked.
    /// The label isn't on the card.
    var checkedFields: [CheckedField] {
        let others = fieldKeys.filter { $0 != numberKey && note(for: $0) != nil }
        let fields = ([numberKey].compactMap { $0 } + others).map { key in
            let text = values[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return CheckedField(
                key: key, title: DocumentFieldStyle.title(for: key),
                value: text.isEmpty ? nil : Self.printed(text, key),
                isNumber: key == numberKey)
        }
        // A date read for a SIM is still noted on a KTP, but it isn't shown or saved there.
        guard hasExpiry, expiryNote != nil else { return fields }
        let validity = CheckedField(
            key: CheckedField.expiryKey, title: DocumentFieldStyle.validityTitle(for: type),
            value: expiry.map(DocumentFieldStyle.dayFirst), isNumber: false)
        return fields + [validity]
    }

    /// A SIM number of digits and dashes is printed with dashes. Anything else shows as typed, the NIK too: it's
    /// only valid as 16 digits together, as printed, and a refused one mustn't look right next to the card.
    private static func printed(_ text: String, _ key: String) -> String {
        let number = DocumentNumber(text)
        guard key == FieldKey.simNumber, !number.isEmpty, text.allSatisfy({ $0.isASCIIDigit || $0 == "-" }) else {
            return text
        }
        return number.shown
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
