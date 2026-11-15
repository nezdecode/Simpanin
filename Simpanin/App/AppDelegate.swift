//
//  AppDelegate.swift
//  Simpanin
//
//  Created by Inez Amanda on 16/11/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    /// Only Apple's keyboards: a third-party keyboard with Full Access could send what's typed, a NIK or a
    /// name, off the phone. iOS keeps them out of secure fields only.
    func application(
        _ application: UIApplication,
        shouldAllowExtensionPointIdentifier extensionPointIdentifier: UIApplication.ExtensionPointIdentifier
    ) -> Bool {
        extensionPointIdentifier != .keyboard
    }
}
