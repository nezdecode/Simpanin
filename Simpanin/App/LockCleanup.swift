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
    let dismissPresented: () -> Void
    let clear: [() -> Void]

    func run() {
        dismissPresented()
        for clear in clear { clear() }
    }

    static func live(in scene: UIWindowScene?) -> LockCleanup {
        LockCleanup(
            dismissPresented: {
                // The cover has its own window above the app's; only the app's windows present anything.
                for window in scene?.windows ?? [] where window.windowLevel == .normal {
                    window.rootViewController?.presentedViewController?.dismiss(animated: false)
                }
            },
            clear: [{ DocumentCameraCache.clear() }, { SharedCopies.clear() }])
    }
}
