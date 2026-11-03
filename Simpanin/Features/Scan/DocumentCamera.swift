//
//  DocumentCamera.swift
//  Simpanin
//
//  Created by Inez Amanda on 16/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI
import VisionKit

/// VisionKit's document camera: finds the page edges, straightens it, and takes several pages. The
/// pages come back as images in memory; nothing goes to Photos, and the copies VisionKit keeps in Caches
/// are removed (`DocumentCameraCache`).
struct DocumentCamera: UIViewControllerRepresentable {
    let onFinish: ([CGImage]) -> Void
    let onCancel: () -> Void
    /// A page couldn't be copied into memory. The scan is never handed on with a page missing.
    let onPageFailed: () -> Void

    /// False in the simulator, which has no camera.
    static var isSupported: Bool { VNDocumentCameraViewController.isSupported }

    /// Whether to offer scanning, in "+" and on the welcome screen. UI tests can hide the camera or
    /// stand in for it.
    static var isAvailable: Bool {
        #if DEBUG
            if UITestSetup.hidesCamera { return false }
            if UITestSetup.scansSynthetically { return true }
        #endif
        return isSupported
    }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let camera = VNDocumentCameraViewController()
        camera.delegate = context.coordinator
        return camera
    }

    func updateUIViewController(_ camera: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    /// Runs whenever the camera leaves the screen, for any reason. Locking the vault removes the screen
    /// that showed the camera without calling the delegate, so this is the one place that always runs.
    static func dismantleUIViewController(_ camera: VNDocumentCameraViewController, coordinator: Coordinator) {
        DocumentCameraCache.clear()
    }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        private let camera: DocumentCamera

        init(_ camera: DocumentCamera) {
            self.camera = camera
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan
        ) {
            let drawn = (0..<scan.pageCount).map { Self.inMemory(scan.imageOfPage(at: $0)) }
            DocumentCameraCache.clear()
            let pages = drawn.compactMap { $0 }
            guard pages.count == drawn.count else { return camera.onPageFailed() }
            camera.onFinish(pages)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            DocumentCameraCache.clear()
            camera.onCancel()
        }

        /// The camera already told the user; closing it is all that's left.
        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController, didFailWithError error: any Error
        ) {
            DocumentCameraCache.clear()
            camera.onCancel()
        }

        /// The camera's images may be backed by its cache files, which are removed next, so each page is
        /// drawn into a bitmap of its own first. Drawing also applies the page's orientation.
        private static func inMemory(_ page: UIImage) -> CGImage? {
            let format = UIGraphicsImageRendererFormat()
            format.scale = page.scale
            return UIGraphicsImageRenderer(size: page.size, format: format).image { _ in page.draw(at: .zero) }
                .cgImage
        }
    }
}
