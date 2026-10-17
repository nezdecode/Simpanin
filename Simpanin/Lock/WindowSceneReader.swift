//
//  WindowSceneReader.swift
//  Simpanin
//
//  Created by Inez Amanda on 17/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI
import UIKit

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
