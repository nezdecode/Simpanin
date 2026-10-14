//
//  RecoveryContent.swift
//  Simpanin
//
//  Created by Inez Amanda on 15/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import Observation
import VaultCore

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

/// A recovery screen's text and its way out, from the design doc's recovery table.
nonisolated struct RecoveryContent: Equatable, Sendable {
    enum Action: Equatable, Sendable {
        case retry, openSettings, startNewVault, openAppStore, dismiss
    }

    let message: LocalizedStringResource
    let action: Action

    init(_ screen: RecoveryScreen) {
        switch screen {
        case .keyMissing: (message, action) = (Self.text("recovery.keyMissing"), .startNewVault)
        case .vaultUnreadable: (message, action) = (Self.text("recovery.vaultUnreadable"), .startNewVault)
        case .passcodeNeeded: (message, action) = (Self.text("recovery.passcodeNeeded"), .openSettings)
        case .passcodeTurnedOff: (message, action) = (Self.text("recovery.passcodeTurnedOff"), .openSettings)
        case .unlockPhoneAndRetry: (message, action) = (Self.text("recovery.unlockPhoneAndRetry"), .retry)
        case .cannotOpenNow: (message, action) = (Self.text("recovery.cannotOpenNow"), .retry)
        case .updateApp: (message, action) = (Self.text("recovery.updateApp"), .openAppStore)
        case .storageFullOnOpen: (message, action) = (Self.text("recovery.storageFullOnOpen"), .retry)
        case .storageFullOnSave: (message, action) = (Self.text("recovery.storageFullOnSave"), .dismiss)
        }
    }

    private static func text(_ key: String.LocalizationValue) -> LocalizedStringResource {
        LocalizedStringResource(key)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.message.key == rhs.message.key && lhs.action == rhs.action
    }
}

extension VaultNotice {
    nonisolated var message: LocalizedStringResource {
        switch self {
        case .newestChangeMayBeLost: LocalizedStringResource("notice.newestChangeMayBeLost")
        case .recoveredFromPages: LocalizedStringResource("notice.recoveredFromPages")
        case .repairWaitingForSpace: LocalizedStringResource("notice.repairWaitingForSpace")
        }
    }
}

/// What the screens need from VaultStore's quarantine calls, so tests can stand in for it.
nonisolated protocol QuarantineStoring: Sendable {
    func quarantineVault(to quarantineDirectory: URL) async throws -> URL?
    func quarantinedVaults(in quarantineDirectory: URL) async throws -> QuarantineListing
    func deleteQuarantinedVault(_ vault: QuarantinedVault) async throws
}

extension VaultStore: QuarantineStoring {}

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
        await lock.unlock()
    }
}
