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
/// use it too. Each page is read when it's shown and let go when it's swiped away or the viewer closes.
struct PageViewer: View {
    let count: Int
    @Binding var selection: Int
    let image: (Int) async -> CGImage?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        TabView(selection: $selection) {
            ForEach(0..<count, id: \.self) { index in
                ViewerPage(index: index, count: count, image: image).tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: count > 1 ? .always : .never))
        .background(.black)
        .overlay(alignment: .topTrailing) {
            Button {
                dismiss()
            } label: {
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
        .accessibilityAction(.escape) { dismiss() }
    }
}

private struct ViewerPage: View {
    let index: Int
    let count: Int
    let image: (Int) async -> CGImage?
    @State private var loaded: CGImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let loaded {
                ZoomableImage(image: loaded)
            } else if failed {
                Text("detail.pageFailed").foregroundStyle(.white).multilineTextAlignment(.center).padding()
            } else {
                ProgressView().tint(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("review.pageOf \(index + 1) \(count)"))
        .task {
            loaded = await image(index)
            failed = loaded == nil
        }
        // Swiped away or closed: the full-size page goes.
        .onDisappear {
            loaded = nil
            failed = false
        }
    }
}

/// A page in a scroll view that zooms. A plain image view: no menu, drag or Live Text.
private struct ZoomableImage: UIViewRepresentable {
    let image: CGImage

    func makeUIView(context: Context) -> UIScrollView {
        let scroll = UIScrollView()
        scroll.minimumZoomScale = 1
        scroll.maximumZoomScale = 5
        scroll.showsHorizontalScrollIndicator = false
        scroll.showsVerticalScrollIndicator = false
        scroll.delegate = context.coordinator
        let view = UIImageView(image: UIImage(cgImage: image))
        view.contentMode = .scaleAspectFit
        view.frame = scroll.bounds
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scroll.addSubview(view)
        context.coordinator.imageView = view
        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator, action: #selector(Coordinator.doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        scroll.addGestureRecognizer(doubleTap)
        return scroll
    }

    func updateUIView(_ scroll: UIScrollView, context: Context) {
        if context.coordinator.imageView?.image?.cgImage !== image {
            context.coordinator.imageView?.image = UIImage(cgImage: image)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var imageView: UIImageView?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        @objc func doubleTapped(_ gesture: UITapGestureRecognizer) {
            guard let scroll = gesture.view as? UIScrollView else { return }
            if scroll.zoomScale > scroll.minimumZoomScale {
                scroll.setZoomScale(scroll.minimumZoomScale, animated: true)
            } else {
                let point = gesture.location(in: imageView)
                let size = CGSize(width: scroll.bounds.width / 3, height: scroll.bounds.height / 3)
                scroll.zoom(
                    to: CGRect(
                        x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width,
                        height: size.height),
                    animated: true)
            }
        }
    }
}
