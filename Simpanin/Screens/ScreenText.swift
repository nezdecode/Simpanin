//
//  ScreenText.swift
//  Simpanin
//
//  Created by Inez Amanda on 14/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

/// Button texts shared by several screens. Every text is in Localizable.xcstrings.
nonisolated enum ScreenText {
    static let open = LocalizedStringResource("button.open")
    static let startNewVault = LocalizedStringResource("button.startNewVault")
    static let retry = LocalizedStringResource("button.retry")
    static let openSettings = LocalizedStringResource("button.openSettings")
    static let openAppStore = LocalizedStringResource("button.openAppStore")
    static let okay = LocalizedStringResource("button.ok")
    static let cancel = LocalizedStringResource("button.cancel")
}
