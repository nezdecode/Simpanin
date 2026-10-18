//
//  QuarantineStoring.swift
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

/// What the screens need from VaultStore's quarantine calls, so tests can stand in for it.
nonisolated protocol QuarantineStoring: Sendable {
    func quarantineVault(to quarantineDirectory: URL) async throws -> URL?
    func quarantinedVaults(in quarantineDirectory: URL) async throws -> QuarantineListing
    func deleteQuarantinedVault(_ vault: QuarantinedVault) async throws
}

extension VaultStore: QuarantineStoring {}
