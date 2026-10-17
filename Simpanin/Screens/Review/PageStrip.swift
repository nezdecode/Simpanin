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

/// Every page of a scan as a small thumbnail, numbered, with the page count beside it, or under it at the
/// accessibility text sizes.
struct PageStrip: View {
    let pages: [CGImage]
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout =
            typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout(spacing: 14))
        layout {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(pages.indices, id: \.self) { index in
                        thumbnail(pages[index], number: index + 1)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            Text("review.pages \(pages.count)").font(.headline)
        }
    }

    private func thumbnail(_ page: CGImage, number: Int) -> some View {
        // A fixed size, whatever the text size: it's a preview, and the count beside it carries the text.
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
            // Read as its number, never as an image, so VoiceOver can't offer to describe the card aloud.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("review.pageOf \(number) \(pages.count)"))
            .accessibilityIdentifier("review.page.\(number)")
    }
}
