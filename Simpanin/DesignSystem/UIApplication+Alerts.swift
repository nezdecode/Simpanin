//
//  UIApplication+Alerts.swift
//  Simpanin
//
//  Created by Inez Amanda on 17/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import UIKit

extension UIApplication {
    /// Whether an alert is on screen in any of the app's windows, still closing included.
    var showsAlert: Bool {
        connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).contains { window in
            var top = window.rootViewController
            while let presented = top?.presentedViewController { top = presented }
            return top is UIAlertController
        }
    }

    /// Focus set, or an alert shown, while an alert is still closing can be dropped, so this waits until the
    /// alert is off the screen, checked rather than guessed with a delay. After two seconds at most it runs
    /// anyway.
    func afterAlertCloses(_ action: @escaping () -> Void) {
        Task {
            for _ in 0..<40 where showsAlert {
                try? await Task.sleep(for: .milliseconds(50))
            }
            action()
        }
    }
}
