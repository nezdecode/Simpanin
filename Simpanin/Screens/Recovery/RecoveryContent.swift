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
        case .saveFailed: (message, action) = (Self.text("recovery.saveFailed"), .dismiss)
        }
    }

    private static func text(_ key: String.LocalizationValue) -> LocalizedStringResource {
        LocalizedStringResource(key)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.message.key == rhs.message.key && lhs.action == rhs.action
    }
}

/// The one extra sentence some recovery screens carry, below the design doc's text.
nonisolated enum RecoveryText {
    static func extra(_ screen: RecoveryScreen) -> LocalizedStringResource? {
        switch screen {
        case .passcodeNeeded: "recovery.extra.passcodeNeeded"
        case .passcodeTurnedOff: "recovery.extra.passcodeTurnedOff"
        case .cannotOpenNow: "recovery.extra.cannotOpenNow"
        case .keyMissing: "recovery.extra.keyMissing"
        case .vaultUnreadable: "recovery.extra.vaultUnreadable"
        case .updateApp: "recovery.extra.updateApp"
        case .unlockPhoneAndRetry, .storageFullOnOpen, .storageFullOnSave, .saveFailed: nil
        }
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
