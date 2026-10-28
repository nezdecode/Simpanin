//
//  PagePager.swift
//  Simpanin
//
//  Created by Inez Amanda on 28/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

/// A document's pages, one per swipe, with "Halaman 1 dari 2" under them. A tap opens the page in the viewer.
struct PagePager: View {
    let pages: [DocumentDetailModel.PageState]
    @Binding var selection: Int
    let transition: Namespace.ID
    let onOpen: (Int) -> Void

    var body: some View {
        VStack(spacing: 8) {
            TabView(selection: $selection) {
                ForEach(pages.indices, id: \.self) { index in
                    page(index)
                        .padding(.horizontal, 16)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            // A fixed height whatever the text size: the page is the picture, the line under it the text.
            .frame(height: 230)
            if pages.count > 1 {
                Text("review.pageOf \(selection + 1) \(pages.count)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    // Each page already says it to VoiceOver.
                    .accessibilityHidden(true)
            }
        }
    }

    @ViewBuilder private func page(_ index: Int) -> some View {
        let label = Text("review.pageOf \(index + 1) \(pages.count)")
        switch pages[index] {
        case .loading:
            card { ProgressView() }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(label)
        case .failed:
            card {
                Text("detail.pageFailed").font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).padding()
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(label)
            .accessibilityValue(Text("detail.pageFailed"))
        case .shown(let image):
            Button {
                onOpen(index)
            } label: {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFit()
                    .clipShape(.rect(cornerRadius: 12))
                    .overlay { RoundedRectangle(cornerRadius: 12).stroke(.separator) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .buttonStyle(.plain)
            .matchedTransitionSource(id: index, in: transition)
            // Read as its number, never as an image, so VoiceOver can't offer to describe the card aloud.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("detail.page.\(index + 1)")
        }
    }

    private func card(@ViewBuilder _ content: () -> some View) -> some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color(.systemGray5))
            .overlay(content: content)
            .aspectRatio(1.585, contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
