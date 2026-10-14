//
//  LockScreens.swift
//  Simpanin
//
//  Created by Inez Amanda on 15/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI
import UIKit

/// Covers everything while the vault is locked or the content must be hidden. Shows the
/// "Buka" button when locked, and the recovery screen when there is one.
struct LockCoverView: View {
    let vault: AppVault
    let lock: LockController

    var body: some View {
        Group {
            if case .recovery(let screen) = lock.state {
                RecoveryView(screen: screen, vault: vault, lock: lock)
            } else {
                VStack(spacing: 24) {
                    Image(systemName: "lock.fill").font(.system(size: 48))
                    if lock.state == .locked {
                        Button {
                            Task { await lock.unlock() }
                        } label: {
                            Text(ScreenText.open)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }
}

/// One row of the recovery table: its text and its way out.
struct RecoveryView: View {
    let screen: RecoveryScreen
    let vault: AppVault
    let lock: LockController
    @State private var startingNewVault = false
    @Environment(\.openURL) private var openURL

    private var content: RecoveryContent { RecoveryContent(screen) }

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "exclamationmark.lock.fill").font(.system(size: 48))
            Text(content.message).multilineTextAlignment(.center)
            switch content.action {
            case .retry:
                Button {
                    Task { await lock.unlock() }
                } label: {
                    Text(ScreenText.retry)
                }
                .buttonStyle(.borderedProminent)
            case .openSettings:
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                } label: {
                    Text(ScreenText.openSettings)
                }
                .buttonStyle(.borderedProminent)
            case .startNewVault:
                Button {
                    startingNewVault = true
                } label: {
                    Text(ScreenText.startNewVault)
                }
                .buttonStyle(.borderedProminent)
            case .openAppStore:
                Button {
                    if let url = URL(string: "itms-apps://apps.apple.com") { openURL(url) }
                } label: {
                    Text(ScreenText.openAppStore)
                }
                .buttonStyle(.borderedProminent)
            case .dismiss:
                EmptyView()
            }
        }
        .padding(32)
        .sheet(isPresented: $startingNewVault) {
            StartNewVaultView(
                model: StartNewVaultModel(
                    store: vault.store, quarantineFolder: vault.locations.quarantine, lock: lock))
        }
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
                }
                if model.failed {
                    Text("startNew.failed").foregroundStyle(.red)
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
            }
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
