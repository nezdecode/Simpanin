//
//  LockCleanup.swift
//  Simpanin
//
//  Created by Inez Amanda on 4/11/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import UIKit

/// What a lock tidies up after the screens it removes: the share sheet and anything else the main window
/// presents goes first, so no target is still reading a copy when the copies are deleted.
struct LockCleanup {
    /// Calls its argument once nothing is presented any more.
    let dismissPresented: (@escaping () -> Void) -> Void
    let clear: [() -> Void]

    func run() {
        var cleared = false
        dismissPresented {
            // Once only: the fallback below can come after the dismiss has finished.
            guard !cleared else { return }
            cleared = true
            for clear in clear { clear() }
        }
    }

    /// UIKit removes a presented screen a moment after `dismiss` returns, so the clears run in its completion.
    /// A dismiss refused mid-animation never completes; the fallback still clears, so no copy waits for launch.
    static func live(in scene: UIWindowScene?) -> LockCleanup {
        LockCleanup(
            dismissPresented: { done in
                // The cover has its own window above the app's; only the app's windows present anything.
                let presented = (scene?.windows ?? []).filter { $0.windowLevel == .normal }
                    .compactMap { $0.rootViewController?.presentedViewController }
                guard !presented.isEmpty else { return done() }
                var left = presented.count
                for controller in presented {
                    controller.dismiss(animated: false) {
                        left -= 1
                        if left == 0 { done() }
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { done() }
            },
            clear: [{ DocumentCameraCache.clear() }, { SharedCopies.clear() }])
    }
}
