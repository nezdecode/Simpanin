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

/// A document's pages, one per swipe, the next one peeking in at the edge, with dots and "Halaman 1 dari 2"
/// under them. A tap opens the page in the viewer. VoiceOver reads it as one element: swipe up or down to
/// change the page, double-tap to enlarge it.
struct PagePager: View {
    let pages: [DocumentDetailModel.PageState]
    @Binding var selection: Int
    let transition: Namespace.ID
    let onOpen: (Int) -> Void

    /// How much of the next page shows, so it's plain there's another to swipe to.
    private static let peek: CGFloat = 18
    private static let spacing: CGFloat = 8

    var body: some View {
        VStack(spacing: 8) {
            scroller
            if pages.count > 1 { indicator }
        }
    }

    private var scroller: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: Self.spacing) {
                ForEach(pages.indices, id: \.self) { index in
                    page(index)
                        .containerRelativeFrame(.horizontal) { length, _ in pageWidth(length) }
                        .id(index)
                }
            }
            .scrollTargetLayout()
        }
        .contentMargins(.horizontal, 16, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: position)
        .scrollIndicators(.hidden)
        .scrollDisabled(pages.count < 2)
        // A fixed height whatever the text size: the page is the picture, the line under it the text.
        .frame(height: 230)
        .accessibilityElement(children: .ignore)
        // The page number is the value, which VoiceOver reads again after each swipe up or down.
        .accessibilityLabel(Text("detail.pages"))
        .accessibilityValue(Text(verbatim: accessibilityValue))
        .accessibilityAddTraits(canOpen(selection) ? .isButton : [])
        .modifier(PageAdjusting(selection: $selection, count: pages.count))
        .accessibilityAction {
            if canOpen(selection) { onOpen(selection) }
        }
        .accessibilityIdentifier("detail.pages")
    }

    private var indicator: some View {
        VStack(spacing: 6) {
            HStack(spacing: 7) {
                ForEach(pages.indices, id: \.self) { index in
                    Circle()
                        .fill(index == selection ? Color.primary : Color.secondary.opacity(0.4))
                        .frame(width: 7, height: 7)
                }
            }
            Text("review.pageOf \(selection + 1) \(pages.count)")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .animation(.default, value: selection)
        // The pager already says it to VoiceOver.
        .accessibilityHidden(true)
    }

    /// "1 dari 2", and why the page doesn't open when it can't.
    private var accessibilityValue: String {
        let number = String(localized: "detail.pageNumber \(selection + 1) \(pages.count)")
        return pageFailed(selection) ? "\(number), \(String(localized: "detail.pageFailed"))" : number
    }

    private func pageWidth(_ length: CGFloat) -> CGFloat {
        pages.count > 1 ? length - Self.peek - Self.spacing : length
    }

    private var position: Binding<Int?> {
        Binding(get: { selection }, set: { if let index = $0 { selection = index } })
    }

    private func canOpen(_ index: Int) -> Bool {
        guard pages.indices.contains(index), case .shown = pages[index] else { return false }
        return true
    }

    private func pageFailed(_ index: Int) -> Bool {
        guard pages.indices.contains(index), case .failed = pages[index] else { return false }
        return true
    }

    @ViewBuilder private func page(_ index: Int) -> some View {
        switch pages[index] {
        case .loading:
            card { ProgressView() }
        case .failed:
            card {
                Text("detail.pageFailed").font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).padding()
            }
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

/// Swiping up or down changes the page for VoiceOver; one page offers no swipe.
private struct PageAdjusting: ViewModifier {
    @Binding var selection: Int
    let count: Int

    func body(content: Content) -> some View {
        if count > 1 {
            content.accessibilityAdjustableAction { direction in
                switch direction {
                case .increment where selection < count - 1: withAnimation { selection += 1 }
                case .decrement where selection > 0: withAnimation { selection -= 1 }
                default: break
                }
            }
        } else {
            content
        }
    }
}
