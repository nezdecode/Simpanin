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
final class CoverWindow<Cover: View> {
    /// Given once: the cover reads its state from the lock, so it never needs replacing.
    private let cover: Cover
    private var window: UIWindow?
    private var captureRegistration: (any UITraitChangeRegistration)?

    init(_ cover: Cover) {
        self.cover = cover
    }

    func show(in scene: UIWindowScene) {
        if window == nil {
            let window = UIWindow(windowScene: scene)
            window.windowLevel = .alert + 1
            window.rootViewController = UIHostingController(rootView: cover)
            self.window = window
        }
        window?.isHidden = false
        hideOtherWindowsFromAccessibility(true, in: scene)
    }

    func hide() {
        window?.isHidden = true
        if let scene = window?.windowScene { hideOtherWindowsFromAccessibility(false, in: scene) }
    }

    /// Covering the screen isn't enough for VoiceOver, which would still read the windows underneath.
    private func hideOtherWindowsFromAccessibility(_ hidden: Bool, in scene: UIWindowScene) {
        for other in scene.windows where other !== window {
            other.accessibilityElementsHidden = hidden
        }
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
