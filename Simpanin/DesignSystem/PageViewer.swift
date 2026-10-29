//
//  PageViewer.swift
//  Simpanin
//
//  Created by Inez Amanda on 28/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI
import UIKit

/// Pages full screen: swipe to the next, pinch or double-tap to zoom. Knows no document, so Periksa data can
/// use it too. The page shown and its two neighbours are kept decoded, the others let go; until one is ready
/// its thumbnail stands in. `current` should be the viewer's own, handed to the screen under it in
/// `onSettle` once a swipe has come to rest and when ✕ closes it, so nothing there changes while a swipe is
/// still moving, and the zoom back lands on the page shown. Not when it has gone: by then the user may be
/// swiping the pages under it, and a late hand-back would undo that.
struct PageViewer: View {
    /// Pages are handed to the viewer at most this many pixels on their longer side: sharp enough to read
    /// a NIK when zoomed in.
    nonisolated static let maxPixelSize = 3_000

    let count: Int
    @Binding var current: Int
    let thumbnail: (Int) -> CGImage?
    let image: (Int) async -> CGImage?
    let onSettle: () -> Void
    @State private var images: [Int: CGImage] = [:]
    @State private var failed: Set<Int> = []
    /// After a memory warning only the page shown is kept, for as long as the viewer is open.
    @State private var lowMemory = false
    @Environment(\.dismiss) private var dismiss
    private let memoryWarnings = NotificationCenter.default.publisher(
        for: UIApplication.didReceiveMemoryWarningNotification)

    var body: some View {
        TabView(selection: $current) {
            ForEach(0..<count, id: \.self) { index in
                page(index).tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: count > 1 ? .always : .never))
        .background(.black)
        .overlay(alignment: .topTrailing) { closeButton }
        .accessibilityAction(.escape) { close() }
        .task(id: current) { await loadAround(current) }
        .task(id: current) {
            // Past halfway the page changes, and the swipe still has to finish.
            guard (try? await Task.sleep(for: .milliseconds(500))) != nil else { return }
            onSettle()
        }
        .onReceive(memoryWarnings) { _ in
            lowMemory = true
            images = images.filter { $0.key == current }
        }
    }

    private var closeButton: some View {
        Button(action: close) {
            Label {
                Text("button.close")
            } icon: {
                Image(systemName: "xmark")
            }
            .labelStyle(.iconOnly)
            .font(.title3.weight(.semibold))
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
        .tint(.white)
        .padding(16)
        .accessibilityIdentifier("viewer.close")
    }

    private func page(_ index: Int) -> some View {
        Group {
            if let shown = images[index] ?? thumbnail(index) {
                ZoomableImage(image: shown)
                    .overlay(alignment: .bottom) {
                        // Only the small copy is left, which won't zoom; say so rather than seem to work.
                        if images[index] == nil, failed.contains(index) {
                            Text("viewer.pageFailed")
                                .font(.subheadline)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(.black.opacity(0.7), in: .capsule)
                                .padding(.bottom, 56)
                        }
                    }
            } else if failed.contains(index) {
                Text("viewer.pageFailed").foregroundStyle(.white).multilineTextAlignment(.center).padding()
            } else {
                ProgressView().tint(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("viewer.pageOf \(index + 1) \(count)"))
        .accessibilityValue(failed.contains(index) ? Text("viewer.pageFailed") : Text(verbatim: ""))
    }

    private func close() {
        // Before the dismissal, so the zoom goes back to the page it closes on.
        onSettle()
        dismiss()
    }

    /// The shown page first, then the next and the one before; any further away is let go.
    private func loadAround(_ index: Int) async {
        images = images.filter { keeps($0.key) }
        for page in [index, index + 1, index - 1] where keeps(page) && images[page] == nil {
            let read = await image(page)
            // A swipe may have moved on meanwhile: a page still next to the one shown is kept all the same.
            if let read {
                if keeps(page) { images[page] = read }
            } else {
                failed.insert(page)
            }
            guard !Task.isCancelled else { return }
        }
    }

    /// The page shown and its neighbours, or after a memory warning the page shown only.
    private func keeps(_ page: Int) -> Bool {
        lowMemory ? page == current : abs(page - current) <= 1 && (0..<count).contains(page)
    }
}

/// A page in a scroll view that zooms, no further than the image's own pixels allow, so it never turns soft.
/// A plain image view: no menu, drag or Live Text.
private struct ZoomableImage: UIViewRepresentable {
    let image: CGImage

    func makeUIView(context: Context) -> ZoomingScrollView {
        let scroll = ZoomingScrollView()
        scroll.showsHorizontalScrollIndicator = false
        scroll.showsVerticalScrollIndicator = false
        scroll.delegate = context.coordinator
        scroll.imageView.image = UIImage(cgImage: image)
        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator, action: #selector(Coordinator.doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        scroll.addGestureRecognizer(doubleTap)
        return scroll
    }

    /// The thumbnail is replaced by the decoded page in place, at the same size on screen.
    func updateUIView(_ scroll: ZoomingScrollView, context: Context) {
        guard scroll.imageView.image?.cgImage !== image else { return }
        scroll.imageView.image = UIImage(cgImage: image)
        scroll.setNeedsLayout()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            (scrollView as? ZoomingScrollView)?.imageView
        }

        @objc func doubleTapped(_ gesture: UITapGestureRecognizer) {
            guard let scroll = gesture.view as? ZoomingScrollView else { return }
            if scroll.zoomScale > scroll.minimumZoomScale {
                scroll.setZoomScale(scroll.minimumZoomScale, animated: true)
            } else {
                let point = gesture.location(in: scroll.imageView)
                let scale = scroll.maximumZoomScale
                let size = CGSize(width: scroll.bounds.width / scale, height: scroll.bounds.height / scale)
                let target = CGRect(
                    x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height)
                scroll.zoom(to: target, animated: true)
            }
        }
    }
}

private final class ZoomingScrollView: UIScrollView {
    let imageView = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        imageView.contentMode = .scaleAspectFit
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(imageView)
        minimumZoomScale = 1
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        if zoomScale == minimumZoomScale { imageView.frame = bounds }
        // One image pixel per screen pixel at most; a thumbnail can't zoom much until the page is ready.
        guard let pixels = imageView.image?.cgImage, bounds.width > 0, bounds.height > 0 else { return }
        let fitted = min(bounds.width / CGFloat(pixels.width), bounds.height / CGFloat(pixels.height))
        maximumZoomScale = max(1, 1 / (fitted * traitCollection.displayScale))
    }
}
