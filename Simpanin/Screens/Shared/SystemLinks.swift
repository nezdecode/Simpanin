//
//  SystemLinks.swift
//  Simpanin
//
//  Created by Inez Amanda on 15/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import UIKit

/// Places outside the app that a screen can send the user to.
enum SystemLinks {
    /// Simpanin's own page in Settings; iOS doesn't allow linking deeper.
    static var settings: URL? { URL(string: UIApplication.openSettingsURLString) }
    static var appStore: URL? { URL(string: "itms-apps://apps.apple.com") }
}
