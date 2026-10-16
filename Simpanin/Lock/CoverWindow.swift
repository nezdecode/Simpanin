//
//  CoverWindow.swift
//  Simpanin
//
//  Created by Inez Amanda on 16/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI
import UIKit

/// The lock cover in a window of its own, above everything the app presents. Sheets, alerts, full-screen
/// covers and VisionKit's camera sit above the root view, so a cover drawn on the root view left them
/// showing in the app switcher and in a recording.
@MainActor
final class CoverWindow {
    private var window: UIWindow?
    private var captureRegistration: (any UITraitChangeRegistration)?

    func show(_ cover: some View, in scene: UIWindowScene) {
        if window == nil {
            let window = UIWindow(windowScene: scene)
            window.windowLevel = .alert + 1
            window.rootViewController = UIHostingController(rootView: cover)
            self.window = window
        }
        window?.isHidden = false
    }

    func hide() {
        window?.isHidden = true
    }

    /// Whether the screen is recorded or mirrored, read from the scene: a view would miss it while a
    /// full-screen presentation has taken it out of the window.
    func watchCapture(in scene: UIWindowScene, onChange: @escaping @MainActor (Bool) -> Void) {
        guard captureRegistration == nil else { return }
        let traits: [UITrait] = [UITraitSceneCaptureState.self]
        onChange(scene.traitCollection.sceneCaptureState == .active)
        captureRegistration = scene.registerForTraitChanges(traits) { (scene: UIWindowScene, _) in
            onChange(scene.traitCollection.sceneCaptureState == .active)
        }
    }
}

/// Reports the window scene the view is in, so RootView can put the cover window in it. A full-screen
/// presentation takes the views under it out of the window, so "no window" is never reported: the app's
/// one scene stays the same while it runs.
struct WindowSceneReader: UIViewRepresentable {
    let onChange: (UIWindowScene) -> Void

    func makeUIView(context: Context) -> SceneView {
        let view = SceneView()
        view.onChange = onChange
        return view
    }

    func updateUIView(_ view: SceneView, context: Context) {
        view.onChange = onChange
    }

    final class SceneView: UIView {
        var onChange: ((UIWindowScene) -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            isUserInteractionEnabled = false
            if let scene = window?.windowScene { onChange?(scene) }
        }
    }
}
