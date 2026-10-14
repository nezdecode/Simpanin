//
//  UITestSetup.swift
//  Simpanin
//
//  Created by Inez Amanda on 15/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

#if DEBUG
    import Foundation
    import VaultCore

    /// Launch arguments the UI tests use. `-SimpaninUITest` starts on a fresh throwaway vault
    /// with an in-memory key. `-SimpaninUITestOpenError <case>` makes opening fail, so a test
    /// lands on a recovery screen; `-SimpaninUITestPasscode notSet` acts as if there's no passcode.
    nonisolated enum UITestSetup {
        static var isActive: Bool { ProcessInfo.processInfo.arguments.contains("-SimpaninUITest") }

        private static func value(after flag: String) -> String? {
            let arguments = ProcessInfo.processInfo.arguments
            guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
            return arguments[index + 1]
        }

        /// The error, and how many opens fail with it. "Any other status" needs two failures in
        /// a row before its screen shows.
        static var openFailure: (error: VaultError, times: Int)? {
            switch value(after: "-SimpaninUITestOpenError") {
            case "keyMissing": (.vaultKeyMissing, 1)
            case "vaultUnreadable": (.vaultUnreadable, 1)
            case "phoneLocked": (.vaultKeyUnavailable(status: -25308), 1)
            case "otherStatus": (.vaultKeyUnavailable(status: nil), 2)
            case "newerVersion": (.unsupportedVersion, 1)
            case "storageFull": (.storageFull, 1)
            default: nil
            }
        }

        static var passcode: PasscodeState {
            value(after: "-SimpaninUITestPasscode") == "notSet" ? .notSet : .set
        }

        @MainActor
        static func lockController(for vault: AppVault) -> LockController {
            let opener: any VaultOpening =
                openFailure.map { ScriptedOpening(store: vault.store, failure: $0.error, times: $0.times) }
                ?? vault.store
            let header = vault.locations.root.appending(path: "vault.json")
            let passcode = passcode
            return LockController(
                vault: opener, passcode: { passcode },
                vaultExists: { FileManager.default.fileExists(atPath: header.path) },
                protectedDataAvailable: { true })
        }
    }

    /// Fails the first opens with a chosen error, then opens the real (throwaway) store.
    actor ScriptedOpening: VaultOpening {
        private let store: VaultStore
        private let failure: VaultError
        private var remaining: Int

        init(store: VaultStore, failure: VaultError, times: Int) {
            self.store = store
            self.failure = failure
            remaining = times
        }

        func open() async throws -> OpenReport {
            if remaining > 0 {
                remaining -= 1
                throw failure
            }
            return try await store.open()
        }

        func lock() async { await store.lock() }
    }
#endif
