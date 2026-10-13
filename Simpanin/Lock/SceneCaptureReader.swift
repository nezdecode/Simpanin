//
//  SceneCaptureReader.swift
//  Simpanin
//
//  Created by Inez Amanda on 14/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI
import UIKit

/// Reports whether the screen is being recorded or mirrored, so content can be hidden.
struct SceneCaptureReader: UIViewRepresentable {
    let onChange: (Bool) -> Void

    func makeUIView(context: Context) -> CaptureView {
        let view = CaptureView()
        view.onChange = onChange
        return view
    }

    func updateUIView(_ view: CaptureView, context: Context) {
        view.onChange = onChange
    }

    final class CaptureView: UIView {
        var onChange: ((Bool) -> Void)?

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            registerForTraitChanges([UITraitSceneCaptureState.self]) { (view: CaptureView, _) in view.report() }
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { nil }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            report()
        }

        private func report() {
            onChange?(traitCollection.sceneCaptureState == .active)
        }
    }
}
