//
//  StartOver.swift
//  Simpanin
//
//  Created by Inez Amanda on 3/11/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

#if DEBUG
    import Foundation
    import Security

    /// DEBUG only. Puts the phone back to a first launch without reinstalling: the vault, Data lama, the
    /// projection and every vault key go. Kunci otomatis and the system permissions stay.
    nonisolated enum StartOver {
        static func run(locations: VaultLocations, accessGroup: String) -> [DeviceCheckLine] {
            let files = [locations.root, locations.quarantine, locations.projectionFolder, locations.oldProjection]
            var lines = files.map { url in
                let result: String
                if !FileManager.default.fileExists(atPath: url.path) {
                    result = "not there"
                } else {
                    do {
                        try FileManager.default.removeItem(at: url)
                        result = "removed"
                    } catch {
                        result = ErrorSummary.describe(error)
                    }
                }
                return DeviceCheckLine(label: "remove \(url.lastPathComponent)", result: result)
            }
            // No account, so the keys of old vaults go too; their folders were removed above.
            let status = SecItemDelete(
                [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: KeychainKeyStore.service,
                    kSecAttrAccessGroup as String: accessGroup,
                    kSecUseDataProtectionKeychain as String: true,
                ] as CFDictionary)
            lines.append(
                DeviceCheckLine(
                    label: "delete vault keys",
                    result: status == errSecSuccess || status == errSecItemNotFound ? "done" : "status \(status)"))
            return lines
        }
    }
#endif
