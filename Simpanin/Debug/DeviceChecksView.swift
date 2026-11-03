//
//  DeviceChecksView.swift
//  Simpanin
//
//  Created by Inez Amanda on 14/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

#if DEBUG
    import LocalAuthentication
    import SwiftUI
    import UIKit

    /// DEBUG only. Runs the open device checks and shows a report to copy and send back.
    struct DeviceChecksView: View {
        let vault: AppVault?
        let lock: LockController
        @State private var lines: [DeviceCheckLine] = []
        @State private var running = false
        @State private var confirmingStartOver = false

        private var accessGroup: String? { AppConfiguration.keychainAccessGroup }

        private var deviceLines: [String] {
            let context = LAContext()
            _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
            let biometry =
                switch context.biometryType {
                case .faceID: "Face ID"
                case .touchID: "Touch ID"
                case .opticID: "Optic ID"
                default: "none"
                }
            return [
                "iOS \(UIDevice.current.systemVersion)", "biometry: \(biometry)",
                "passcode: \(PasscodeState.current())",
            ]
        }

        /// The lock's own log survives the locking, unlike this screen's state.
        private var report: String {
            let lockLines = lock.attemptLog.enumerated().map {
                DeviceCheckLine(label: "lock \($0.offset + 1)", result: $0.element)
            }
            return DeviceChecks.report(device: deviceLines, lines: lines + lockLines)
        }

        var body: some View {
            Form {
                Section {
                    NavigationLink("Coba pindai") { ScanTryView() }
                } footer: {
                    Text("Scan a document and see what Vision and the parsers read. Saves nothing.")
                }
                Section("1–3. Data Protection") {
                    Button("Check protection classes") { run(checkFiles) }
                }
                Section {
                    Button("Add test item") { runKeychain { DeviceChecks.addTestItem(accessGroup: $0) } }
                } header: {
                    Text("4. SecItemAdd")
                } footer: {
                    Text(
                        "Tap once with the passcode on. Then turn the passcode off in Settings, "
                            + "come back and tap again."
                    )
                }
                Section {
                    Button("Read: let it succeed") { read("succeeded") }
                    Button("Read: tap Batal") { read("tapped Batal") }
                    Button("Read: go to the home screen during the prompt") { read("sent to background") }
                    Button("Delete test item") { runKeychain { DeviceChecks.deleteTestItem(accessGroup: $0) } }
                } header: {
                    Text("5–6. Prompt and cancel")
                } footer: {
                    Text("Add the test item first, with the passcode on. After \"let it succeed\", answer below.")
                }
                Section("6. After the successful read") {
                    Button("I saw one prompt") { note("prompts seen", "1") }
                    Button("I saw two or more prompts") { note("prompts seen", "2 or more") }
                    Button("It showed \"\(KeychainKeyStore.promptReason)\"") { note("reason text shown", "yes") }
                    Button("It didn't show that text") { note("reason text shown", "no") }
                }
                Section {
                    Button("Lock, then open again in 5 seconds") { lockThenOpen() }
                } header: {
                    Text("7. Lock the phone during open")
                } footer: {
                    Text(
                        "The vault locks now and opens again after 5 seconds. As soon as the prompt appears, "
                            + "press the side button. Then unlock the phone, open Simpanin, come back here "
                            + "and copy the report. The lock lines show what came back."
                    )
                }
                Section {
                    Button("Start over", role: .destructive) { confirmingStartOver = true }
                        // UI tests use a throwaway vault but the real access group, so the real keys would go.
                        .disabled(vault == nil || accessGroup == nil || UITestSetup.isActive)
                } header: {
                    Text("First launch")
                } footer: {
                    Text(
                        "Deletes every document, Data lama and the vault keys, then closes Simpanin. "
                            + "Open it again to see the welcome. If something stays, the keys are kept and "
                            + "the report below says what happened."
                    )
                }
                Section("Report") {
                    Text(report).font(.caption.monospaced()).textSelection(.enabled)
                    Button("Copy report") { UIPasteboard.general.string = report }
                    Button("Clear", role: .destructive) { lines = [] }
                }
            }
            .navigationTitle("Device checks")
            .disabled(running)
            .confirmationDialog("Delete every document on this phone?", isPresented: $confirmingStartOver) {
                Button("Start over", role: .destructive) { startOver() }
            }
        }

        /// Runs on after the vault locks and this screen disappears, through the real controller.
        private func lockThenOpen() {
            let lock = lock
            Task {
                await lock.lock()
                try? await Task.sleep(for: .seconds(5))
                await lock.unlock()
            }
        }

        /// Locked first, so the store writes nothing while its folder goes. Closed after, so the next launch
        /// is a real first launch.
        private func startOver() {
            guard let vault, let accessGroup else { return }
            let lock = lock
            Task {
                await lock.lock()
                let results = await Task.detached {
                    StartOver.run(locations: vault.locations, accessGroup: accessGroup)
                }.value
                // The lock has closed this screen, so a step that failed goes to the lock's log, which the
                // report shows; the app only closes when everything went.
                guard results.allSatisfy({ ["removed", "not there", "done"].contains($0.result) }) else {
                    for line in results { lock.log("start over, \(line.label): \(line.result)") }
                    return
                }
                exit(0)
            }
        }

        private func note(_ label: String, _ result: String) {
            lines.append(DeviceCheckLine(label: label, result: result))
        }

        private func run(_ work: @escaping () async throws -> [DeviceCheckLine]) {
            running = true
            Task {
                do {
                    lines += try await work()
                } catch {
                    note("error", String(describing: type(of: error)))
                }
                running = false
            }
        }

        private func checkFiles() async throws -> [DeviceCheckLine] {
            let support = try FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            guard let group = AppConfiguration.appGroup,
                let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
            else { return [DeviceCheckLine(label: "app group", result: "missing")] }
            var result = try await DeviceChecks.scratchVaultProtection(
                applicationSupport: support, appGroup: container)
            if let vault, FileManager.default.fileExists(atPath: vault.locations.root.path) {
                result += try DeviceChecks.vaultClasses(
                    root: vault.locations.root, projection: vault.locations.projection
                )
                .map { DeviceCheckLine(label: "real \($0.label)", result: $0.result) }
            }
            result += try DeviceChecks.renameKeepsClass(in: support)
            result += try DeviceChecks.newFileTakesFolderClass(in: support)
            return result
        }

        private func read(_ scenario: String) {
            runKeychain { DeviceChecks.readTestItem(accessGroup: $0, scenario: scenario) }
        }

        /// Keychain calls block while a prompt is up, so they run off the main actor.
        private func runKeychain(_ check: @escaping @Sendable (String) -> DeviceCheckLine) {
            guard let accessGroup else {
                note("keychain access group", "missing")
                return
            }
            run { [await Task.detached { check(accessGroup) }.value] }
        }
    }
#endif
