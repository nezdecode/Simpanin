//
//  PageStrip.swift
//  Simpanin
//
//  Created by Inez Amanda on 17/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

/// Every page of a scan as a small thumbnail, numbered; the page count and the notes are in the section's
/// footer. A page read as another document gets a badge, and VoiceOver reads its note with its number.
struct PageStrip: View {
    let pages: [CGImage]
    let notes: PageNotes
    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(pages.indices, id: \.self) { index in
                    thumbnail(pages[index], index: index)
                }
            }
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
    }

    private func thumbnail(_ page: CGImage, index: Int) -> some View {
        let number = index + 1
        let marked = notes.notes[index]?.isMarked == true
        return
            // A fixed size, whatever the text size: it's a preview, and the footer carries the text.
            Image(decorative: page, scale: 1)
            .resizable()
            .scaledToFill()
            .frame(width: 112, height: 72)
            .clipShape(.rect(cornerRadius: 10))
            // A thin edge, so a bright page still stands out from the row.
            .overlay { RoundedRectangle(cornerRadius: 10).stroke(.separator) }
            .overlay(alignment: .bottomTrailing) {
                Text(verbatim: "\(number)")
                    .font(.caption2.bold())
                    .dynamicTypeSize(...DynamicTypeSize.large)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.6), in: .capsule)
                    .padding(4)
            }
            .overlay(alignment: .topTrailing) {
                if marked {
                    // Fixed like the page number: the footer is the text that grows.
                    IconBadge(
                        systemImage: "exclamationmark.triangle.fill", size: 20, symbolFont: .caption2.bold(),
                        tint: Color(.onWarning), background: Color(.warningIcon)
                    )
                    .dynamicTypeSize(...DynamicTypeSize.large)
                    .padding(4)
                }
            }
            // Read as its number, never as an image, so VoiceOver can't offer to describe the card aloud.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: notes.accessibilityLabel(page: index)))
            .accessibilityIdentifier("review.page.\(number)")
    }
}
