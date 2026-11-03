//
//  StartNewVaultModel.swift
//  Simpanin
//
//  Created by Inez Amanda on 14/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Observation
import SwiftUI
import VaultCore

/// "Mulai vault baru": typing the word moves the old vault aside, unchanged, then opens a new
/// one. Nothing is deleted; the old files stay under "Data lama".
@MainActor @Observable
final class StartNewVaultModel {
    static let confirmationWord = "MULAI BARU"

    var typed = ""
    private(set) var failed = false
    private let store: any QuarantineStoring
    private let quarantineFolder: URL
    private let lock: LockController

    init(store: any QuarantineStoring, quarantineFolder: URL, lock: LockController) {
        self.store = store
        self.quarantineFolder = quarantineFolder
        self.lock = lock
    }

    static func matches(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespaces).uppercased() == confirmationWord
    }

    var canConfirm: Bool { Self.matches(typed) }

    func confirm() async {
        guard canConfirm else { return }
        do {
            _ = try await store.quarantineVault(to: quarantineFolder)
        } catch {
            failed = true
            return
        }
        failed = false
        // The folder is empty now; the user has already chosen, so no welcome.
        await lock.createVault(then: nil)
    }
}
