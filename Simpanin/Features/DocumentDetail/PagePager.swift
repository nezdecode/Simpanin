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
    @State private var position = ScrollPosition()
    @State private var width: CGFloat = 0
    /// The page on screen, so only a page chosen elsewhere scrolls the pages.
    @State private var shown = 0

    var body: some View {
        VStack(spacing: 8) {
            scroller
            if pages.count > 1 { indicator }
        }
    }

    private var scroller: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: PagerLayout.spacing) {
                ForEach(pages.indices, id: \.self) { index in
                    page(index)
                        .frame(width: PagerLayout(count: pages.count, width: width).pageWidth)
                        .id(index)
                }
            }
            .padding(.horizontal, PagerLayout.margin)
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(PageSnapping(count: pages.count))
        .scrollPosition($position)
        .onGeometryChange(for: CGFloat.self) {
            $0.size.width
        } action: { newWidth in
            width = newWidth
            position.scrollTo(x: PagerLayout(count: pages.count, width: newWidth).offset(for: selection))
        }
        .onScrollTargetVisibilityChange(idType: Int.self, threshold: 0.6) { visible in
            guard let first = visible.first else { return }
            shown = first
            if selection != first { selection = first }
        }
        // A page chosen elsewhere (the viewer, VoiceOver) is scrolled to straight away, even under the viewer.
        .onChange(of: selection) { _, index in
            if index != shown { position.scrollTo(x: PagerLayout(count: pages.count, width: width).offset(for: index)) }
        }
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

/// One page per swipe, ending where `PagerLayout` puts it.
private struct PageSnapping: ScrollTargetBehavior {
    let count: Int

    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        guard count > 1 else { return }
        target.rect.origin.x = PagerLayout(count: count, width: context.containerSize.width)
            .target(from: context.originalTarget.rect.minX, proposed: target.rect.minX)
    }
}

/// Where each page sits, so a swipe's end and a page chosen elsewhere land the same: a middle page centered
/// with `peek` of each neighbour showing, the first and last against their margins.
nonisolated struct PagerLayout: Equatable {
    static let peek: CGFloat = 18
    static let spacing: CGFloat = 8
    static let margin: CGFloat = 16

    let count: Int
    /// The scroll view's width.
    let width: CGFloat

    var pageWidth: CGFloat {
        max(0, count > 1 ? width - 2 * (Self.peek + Self.spacing) : width - 2 * Self.margin)
    }

    private var step: CGFloat { pageWidth + Self.spacing }
    private var contentWidth: CGFloat { 2 * Self.margin + CGFloat(count) * step - Self.spacing }

    /// The scroll offset that shows a page.
    func offset(for page: Int) -> CGFloat {
        let centered = Self.margin + CGFloat(page) * step + pageWidth / 2 - width / 2
        return min(max(centered, 0), max(contentWidth - width, 0))
    }

    /// Where a swipe that began at `start` ends: the page nearest where it would stop, one page away at most.
    func target(from start: CGFloat, proposed: CGFloat) -> CGFloat {
        let first = page(at: start)
        return offset(for: min(max(page(at: proposed), first - 1), first + 1))
    }

    /// The page nearest the middle of the screen at a scroll offset.
    func page(at offset: CGFloat) -> Int {
        guard count > 1, step > 0 else { return 0 }
        let middle = offset + width / 2
        return min(max(Int(((middle - Self.margin - pageWidth / 2) / step).rounded()), 0), count - 1)
    }
}
