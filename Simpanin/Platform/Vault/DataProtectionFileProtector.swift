//
//  DataProtectionFileProtector.swift
//  Simpanin
//
//  Created by Inez Amanda on 14/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import VaultCore

/// Sets the Data Protection class VaultCore asks for, on files and on the folders it creates.
nonisolated struct DataProtectionFileProtector: FileProtector {
    static func protectionType(for protection: FileProtectionClass) -> FileProtectionType {
        switch protection {
        case .complete: .complete
        case .completeUntilFirstUserAuthentication: .completeUntilFirstUserAuthentication
        }
    }

    func protect(_ url: URL, as protection: FileProtectionClass) throws {
        try FileManager.default.setAttributes(
            [.protectionKey: Self.protectionType(for: protection)], ofItemAtPath: url.path)
    }
}
