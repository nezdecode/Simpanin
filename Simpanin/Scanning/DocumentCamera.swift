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
/// pages come back as images in memory; nothing goes to Photos.
struct DocumentCamera: UIViewControllerRepresentable {
    let onFinish: ([CGImage]) -> Void
    let onCancel: () -> Void

    /// False in the simulator, which has no camera.
    static var isSupported: Bool { VNDocumentCameraViewController.isSupported }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let camera = VNDocumentCameraViewController()
        camera.delegate = context.coordinator
        return camera
    }

    func updateUIViewController(_ camera: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        private let camera: DocumentCamera

        init(_ camera: DocumentCamera) {
            self.camera = camera
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan
        ) {
            camera.onFinish((0..<scan.pageCount).compactMap { scan.imageOfPage(at: $0).cgImage })
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            camera.onCancel()
        }

        /// The camera already told the user; closing it is all that's left.
        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController, didFailWithError error: any Error
        ) {
            camera.onCancel()
        }
    }
}
