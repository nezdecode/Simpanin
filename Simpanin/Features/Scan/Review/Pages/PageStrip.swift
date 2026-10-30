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
/// footer. A page read as another document gets a badge, and VoiceOver reads its note with its number. A tap
/// opens the page full screen.
struct PageStrip: View {
    let thumbnails: [PageThumbnail]
    let notes: PageNotes
    /// The viewer zooms out of the page tapped and back into the one it closes on.
    let transition: Namespace.ID
    let onOpen: (Int) -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(thumbnails.indices, id: \.self) { index in
                    Button {
                        onOpen(index)
                    } label: {
                        thumbnail(thumbnails[index].image, index: index)
                    }
                    // Plain, so a Form row with several buttons fires only the one tapped, and the page isn't tinted.
                    .buttonStyle(.plain)
                    .matchedTransitionSource(id: index, in: transition)
                    .opacity(isEnabled ? 1 : 0.4)
                    // Read as its number, never as an image, so VoiceOver can't offer to describe the card aloud.
                    .accessibilityLabel(Text(verbatim: notes.accessibilityLabel(page: index)))
                    .accessibilityHint(Text("review.pageOpenHint"))
                    .accessibilityIdentifier("review.page.\(index + 1)")
                }
            }
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
    }

    private func thumbnail(_ page: CGImage?, index: Int) -> some View {
        let number = index + 1
        let marked = notes.notes[index]?.isMarked == true
        return Group {
            if let page {
                Image(decorative: page, scale: 1).resizable().scaledToFill()
            } else {
                // The scan itself is fine and saved in full; only its preview is missing.
                Color(.systemGray5)
            }
        }
        // A fixed size, whatever the text size: it's a preview, and the footer carries the text.
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
        .accessibilityElement(children: .ignore)
    }
}
