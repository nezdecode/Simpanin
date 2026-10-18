//
//  AppConfiguration.swift
//  Simpanin
//
//  Created by Inez Amanda on 14/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

/// Values the build writes into Info.plist, so the code always matches the entitlements.
nonisolated enum AppConfiguration {
    /// The Keychain access group with the team prefix, like the entitlement.
    static var keychainAccessGroup: String? { value(for: "SimpaninKeychainAccessGroup") }
    /// The App Group that holds projection.json.
    static var appGroup: String? { value(for: "SimpaninAppGroup") }

    private static func value(for key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String, !value.isEmpty,
            !value.contains("$(")
        else { return nil }
        return value
    }
}
