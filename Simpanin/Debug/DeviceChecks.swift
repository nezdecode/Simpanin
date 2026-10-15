//
//  DeviceChecks.swift
//  Simpanin
//
//  Created by Inez Amanda on 14/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

#if DEBUG
    import Foundation
    import LocalAuthentication
    import Security
    import VaultCore

    /// One result: a label such as "index" and a status or attribute name.
    nonisolated struct DeviceCheckLine: Equatable, Sendable {
        let label: String
        let result: String
    }

    /// The open device checks from the design doc. Results are labels, statuses and attribute
    /// names only: never file names (page files are named after ids), ids or values.
    nonisolated enum DeviceChecks {
        // MARK: - Data Protection

        static func protectionName(_ url: URL) -> String {
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            return (attributes?[.protectionKey] as? FileProtectionType)?.rawValue ?? "none"
        }

        /// The class of every file and folder of a vault, by label.
        static func vaultClasses(root: URL, projection: URL) throws -> [DeviceCheckLine] {
            var lines = [DeviceCheckLine(label: "vault folder", result: protectionName(root))]
            var pages = 0
            for path in try FileManager.default.subpathsOfDirectory(atPath: root.path).sorted() {
                let label: String
                switch path {
                case "pages": label = "pages folder"
                case VaultStore.headerFileName: label = "vault header"
                case "index.enc": label = "index"  // swiftlint:disable:this vault_file_names
                case "index.prev.enc": label = "previous index"  // swiftlint:disable:this vault_file_names
                default:
                    if path.hasPrefix("pages/") {
                        pages += 1
                        label = "page \(pages)"
                    } else {
                        label = "other file"
                    }
                }
                lines.append(DeviceCheckLine(label: label, result: protectionName(root.appending(path: path))))
            }
            lines.append(
                DeviceCheckLine(
                    label: "projection folder", result: protectionName(projection.deletingLastPathComponent())))
            lines.append(DeviceCheckLine(label: "projection", result: protectionName(projection)))
            return lines
        }

        /// A throwaway vault with the real FileProtector, a synthetic document and one edit, so
        /// every kind of file exists. It never touches the real vault and is deleted afterwards.
        static func scratchVaultProtection(applicationSupport: URL, appGroup: URL) async throws -> [DeviceCheckLine] {
            let scratch = applicationSupport.appending(path: "DeviceCheck", directoryHint: .isDirectory)
            let scratchGroup = appGroup.appending(path: "DeviceCheck", directoryHint: .isDirectory)
            let cleanUp = {
                try? FileManager.default.removeItem(at: scratch)
                try? FileManager.default.removeItem(at: scratchGroup)
            }
            cleanUp()
            defer { cleanUp() }
            let locations = VaultLocations(applicationSupport: scratch, appGroupContainer: scratchGroup)
            let store = VaultStore(
                rootDirectory: locations.root, projectionURL: locations.projection, keyStore: PreviewKeyStore(),
                fileProtector: DataProtectionFileProtector())
            try await store.open()
            let fields = DocumentFields(["nik": "0012345678901234"])
            let id = try await store.createDocument(
                type: .ktp, expiry: nil, pinned: false, fields: fields, pages: [Data(repeating: 7, count: 2_000)])
            try await store.editDocument(id, type: .ktp, label: nil, expiry: nil, pinned: true, fields: fields)
            return try vaultClasses(root: locations.root, projection: locations.projection)
        }

        /// A file born at the background class, set to Complete, then renamed like VaultCore's
        /// temp-file write. The rename should keep Complete.
        static func renameKeepsClass(in folder: URL) throws -> [DeviceCheckLine] {
            let directory = folder.appending(path: "RenameCheck", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: directory.path)
            let temp = directory.appending(path: "temp")
            let target = directory.appending(path: "target")
            try Data(repeating: 1, count: 64).write(to: temp)
            let born = protectionName(temp)
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.complete], ofItemAtPath: temp.path)
            guard rename(temp.path, target.path) == 0 else { throw POSIXError(.EIO) }
            return [
                DeviceCheckLine(label: "rename: new file in a background-class folder", result: born),
                DeviceCheckLine(label: "rename: after protect, then rename", result: protectionName(target)),
            ]
        }

        /// A folder set to Complete, then a new file written into it without a class of its own.
        static func newFileTakesFolderClass(in folder: URL) throws -> [DeviceCheckLine] {
            let directory = folder.appending(path: "FolderCheck", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.complete], ofItemAtPath: directory.path)
            let file = directory.appending(path: "new")
            try Data(repeating: 2, count: 64).write(to: file)
            return [
                DeviceCheckLine(label: "folder: Complete folder", result: protectionName(directory)),
                DeviceCheckLine(label: "folder: new file inside it", result: protectionName(file)),
            ]
        }

        // MARK: - Keychain, with a test item that has the vault key's settings

        static let testService = "simpanin.devicecheck"

        private static func testItemQuery(accessGroup: String) -> [String: Any] {
            [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: testService,
                kSecAttrAccount as String: "check",
                kSecAttrAccessGroup as String: accessGroup,
                kSecAttrSynchronizable as String: false,
                kSecUseDataProtectionKeychain as String: true,
            ]
        }

        static func statusName(_ status: OSStatus) -> String {
            let message = SecCopyErrorMessageString(status, nil) as String? ?? ""
            return "\(status) \(message)"
        }

        /// Replaces the test item, like creating a vault key. Blocks; call off the main actor.
        static func addTestItem(accessGroup: String) -> DeviceCheckLine {
            SecItemDelete(testItemQuery(accessGroup: accessGroup) as CFDictionary)
            guard
                let access = SecAccessControlCreateWithFlags(
                    nil, KeychainKeyStore.accessibility, KeychainKeyStore.accessControlFlags, nil)
            else { return DeviceCheckLine(label: "SecItemAdd (.userPresence)", result: "access control failed") }
            var attributes = testItemQuery(accessGroup: accessGroup)
            attributes[kSecAttrAccessControl as String] = access
            attributes[kSecValueData as String] = Data(repeating: 0, count: 32)
            let status = SecItemAdd(attributes as CFDictionary, nil)
            return DeviceCheckLine(label: "SecItemAdd (.userPresence)", result: statusName(status))
        }

        /// Reads the test item the way KeychainKeyStore reads the vault key: an unevaluated
        /// LAContext, so the Keychain shows the prompt. Blocks; call off the main actor.
        static func readTestItem(accessGroup: String, scenario: String) -> DeviceCheckLine {
            let context = LAContext()
            context.localizedReason = KeychainKeyStore.promptReason
            var query = testItemQuery(accessGroup: accessGroup)
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            query[kSecUseAuthenticationContext as String] = context
            var result: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            return DeviceCheckLine(label: "read (\(scenario))", result: statusName(status))
        }

        static func deleteTestItem(accessGroup: String) -> DeviceCheckLine {
            let status = SecItemDelete(testItemQuery(accessGroup: accessGroup) as CFDictionary)
            return DeviceCheckLine(label: "delete test item", result: statusName(status))
        }

        // MARK: - Report

        static func report(device: [String], lines: [DeviceCheckLine]) -> String {
            (["Simpanin device checks"] + device + [""] + lines.map { "\($0.label): \($0.result)" })
                .joined(separator: "\n")
        }
    }
#endif
