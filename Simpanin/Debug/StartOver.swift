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
            var lines = removeFiles([
                locations.root, locations.quarantine, locations.projectionFolder, locations.oldProjection,
            ])
            // Keys without their files would leave a vault that can't open, so they only go once the files have.
            guard succeeded(lines) else {
                lines.append(DeviceCheckLine(label: "delete vault keys", result: "skipped, a folder stayed"))
                return lines
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

        /// One line per item: "removed", "not there", or why it stayed.
        static func removeFiles(_ urls: [URL]) -> [DeviceCheckLine] {
            urls.map { url in
                // Only "no such file" means gone: `fileExists` also says false for a folder it can't look in,
                // and taking that for gone would delete the keys of a vault still on disk.
                let result: String
                do {
                    _ = try FileManager.default.attributesOfItem(atPath: url.path)
                    try FileManager.default.removeItem(at: url)
                    result = "removed"
                } catch CocoaError.fileReadNoSuchFile, CocoaError.fileNoSuchFile {
                    result = "not there"
                } catch {
                    result = ErrorSummary.describe(error)
                }
                return DeviceCheckLine(label: "remove \(url.lastPathComponent)", result: result)
            }
        }

        /// Whether every step went, so the keys may go and the app may close.
        static func succeeded(_ lines: [DeviceCheckLine]) -> Bool {
            lines.allSatisfy { ["removed", "not there", "done"].contains($0.result) }
        }
    }
#endif
