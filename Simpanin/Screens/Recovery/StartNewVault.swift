//
//  StartNewVault.swift
//  Simpanin
//
//  Created by Inez Amanda on 15/10/26.
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
        await lock.unlock()
    }
}

/// "Mulai vault baru" with its typed confirmation.
struct StartNewVaultView: View {
    @State var model: StartNewVaultModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("startNew.explanation")
                    Text("startNew.instruction \(StartNewVaultModel.confirmationWord)")
                    TextField(StartNewVaultModel.confirmationWord, text: $model.typed)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("startNew.field")
                }
                if model.failed {
                    Text("startNew.failed").foregroundStyle(Color("Destructive"))
                }
                Button {
                    Task {
                        await model.confirm()
                        if !model.failed { dismiss() }
                    }
                } label: {
                    Text(ScreenText.startNewVault)
                }
                .disabled(!model.canConfirm)
                .accessibilityIdentifier("startNew.confirm")
            }
            .navigationTitle(Text("startNew.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text(ScreenText.cancel)
                    }
                }
            }
        }
    }
}
