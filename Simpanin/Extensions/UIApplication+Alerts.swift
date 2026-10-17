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
}
