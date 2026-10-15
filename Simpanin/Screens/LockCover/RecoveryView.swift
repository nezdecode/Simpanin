//
//  RecoveryView.swift
//  Simpanin
//
//  Created by Inez Amanda on 14/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

/// One row of the recovery table: an icon for its tone, the design doc's text, at most one more
/// sentence, and its way out.
struct RecoveryView: View {
    let screen: RecoveryScreen
    let vault: AppVault
    let lock: LockController
    @State private var startingNewVault = false
    @Environment(\.openURL) private var openURL

    private var content: RecoveryContent { RecoveryContent(screen) }
    private var isPasscodeScreen: Bool { content.action == .openSettings }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Spacer(minLength: 40)
            IconBadge(
                systemImage: content.tone.systemImage, size: 64, symbolFont: .system(size: 30, weight: .semibold),
                tint: toneColor,
                background: toneColor.opacity(0.14))
            Text(content.message)
                .font(.title2.bold())
                .accessibilityIdentifier("recovery.message")
            if let extra = RecoveryText.extra(screen) {
                Text(extra).foregroundStyle(.secondary)
            }
            if isPasscodeScreen { PasscodeSteps() }
            if screen == .storageFullOnOpen {
                Text("storageFull.hint").font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            actionButton
            if isPasscodeScreen {
                Text("onboarding.recheck")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .sheet(isPresented: $startingNewVault) {
            StartNewVaultView(
                model: StartNewVaultModel(
                    store: vault.store, quarantineFolder: vault.locations.quarantine, lock: lock))
        }
    }

    private var actionButton: some View {
        Group {
            switch content.action {
            case .retry:
                button(ScreenText.retry) { Task { await lock.unlock() } }
            case .openSettings:
                button(ScreenText.openSettings) {
                    if let url = URL.appSettings { openURL(url) }
                }
            case .startNewVault:
                // A decision rather than the obvious next step, so the softer button. Not red:
                // starting a new vault deletes nothing.
                button(ScreenText.startNewVault, emphasis: .secondary) { startingNewVault = true }
            case .openAppStore:
                button(ScreenText.openAppStore) {
                    if let url = URL.appStore { openURL(url) }
                }
            case .dismiss:
                EmptyView()
            }
        }
        .accessibilityIdentifier("recovery.action")
    }

    private func button(
        _ title: LocalizedStringResource, emphasis: FullWidthButtonStyle.Emphasis = .primary,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) { Text(title) }
            .buttonStyle(.fullWidth(emphasis))
    }

    private var toneColor: Color {
        switch content.tone {
        case .needsAction, .update: .accentColor
        case .decision: Color(.onWarning)
        case .temporary: .secondary
        }
    }
}
