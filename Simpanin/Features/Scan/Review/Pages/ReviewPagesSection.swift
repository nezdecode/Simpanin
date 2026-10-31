//
//  ReviewPagesSection.swift
//  Simpanin
//
//  Created by Inez Amanda on 30/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

/// Periksa data's pages: the strip, and under it the page count and the notes. A tap on a page asks for it
/// to be enlarged, so a marked field can be checked against the card.
struct ReviewPagesSection: View {
    let thumbnails: [PageThumbnail]
    let notes: PageNotes
    /// Under the count, like "Foto aslinya masih ada di app Foto."
    var footnote: LocalizedStringResource?
    /// A rescan's pages are being read; the ones shown are about to be replaced, so they don't open.
    let reading: Bool
    let transition: Namespace.ID
    let onOpen: (Int) -> Void

    var body: some View {
        Section {
            PageStrip(thumbnails: thumbnails, notes: notes, transition: transition, onOpen: onOpen)
                .disabled(reading)
        } footer: {
            footer
        }
    }

    /// "N halaman", then which page the fields came from and what other pages were read as, one text each.
    /// A page with a badge is said in amber like a mark, so it's seen when the screen is skimmed.
    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("review.pages \(thumbnails.count)")
            if let footnote { Text(footnote) }
            ForEach(notes.lines, id: \.text) { line in
                if line.isMarked { WarningText(verbatim: line.text) } else { Text(verbatim: line.text) }
            }
        }
    }
}
