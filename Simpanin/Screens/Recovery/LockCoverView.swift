//
//  LockCoverView.swift
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

/// Covers everything while the vault is locked or the content must be hidden. Shows "Buka" when
/// locked, and the recovery screen when there is one.
struct LockCoverView: View {
    let vault: AppVault
    let lock: LockController

    var body: some View {
        if case .recovery(let screen) = lock.state {
            RecoveryView(screen: screen, vault: vault, lock: lock)
        } else {
            LockedView(lock: lock)
        }
    }
}

/// The dark cover with the app's name and the "Buka" button.
struct LockedView: View {
    let lock: LockController
    private let method = UnlockMethod.current()

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 16) {
                IconBadge(
                    symbol: "lock.shield", size: 88, symbolFont: .system(size: 44), tint: Color(.lockIcon),
                    background: Color(.lockIconBackground), outline: .rounded(22))
                Text("lock.title").font(.title.bold())
                Text("lock.subtitle")
                    .foregroundStyle(Color(.lockSecondaryText))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)
            Spacer()
            if lock.state == .locked {
                VStack(spacing: 12) {
                    Button {
                        Task { await lock.unlock() }
                    } label: {
                        Label {
                            Text(ScreenText.open)
                        } icon: {
                            Image(systemName: method.symbol)
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 54)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color(.lockBackground))
                    .background(.white, in: .capsule)
                    .accessibilityIdentifier("lock.open")
                    Text(method.caption)
                        .font(.footnote)
                        .foregroundStyle(Color(.lockSecondaryText))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.lockBackground))
    }
}

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
                symbol: tone.symbol, size: 64, symbolFont: .system(size: 30, weight: .semibold), tint: tone.colour,
                background: tone.colour.opacity(0.14))
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

    @ViewBuilder private var actionButton: some View {
        Group {
            switch content.action {
            case .retry:
                button(ScreenText.retry) { Task { await lock.unlock() } }
            case .openSettings:
                button(ScreenText.openSettings) {
                    if let url = SystemLinks.settings { openURL(url) }
                }
            case .startNewVault:
                // Not red: starting a new vault deletes nothing.
                button(ScreenText.startNewVault) { startingNewVault = true }
            case .openAppStore:
                button(ScreenText.openAppStore) {
                    if let url = SystemLinks.appStore { openURL(url) }
                }
            case .dismiss:
                EmptyView()
            }
        }
        .buttonStyle(.fullWidth)
        .accessibilityIdentifier("recovery.action")
    }

    private func button(_ title: LocalizedStringResource, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(title) }
    }

    /// The design's four tones follow what the user has to do, not how bad the error is.
    private var tone: (symbol: String, colour: Color) {
        switch content.action {
        case .openSettings: ("lock", .accentColor)
        case .startNewVault: ("questionmark", Color(.onWarning))
        case .openAppStore: ("arrow.up", .accentColor)
        case .retry, .dismiss: ("arrow.clockwise", .secondary)
        }
    }
}

/// The three steps to turn on a passcode. The button can only open Simpanin's own page in
/// Settings, so the steps start from the main Settings screen.
struct PasscodeSteps: View {
    private let method = UnlockMethod.current()

    private var stepTwo: LocalizedStringResource {
        switch method {
        case .faceID, .faceIDTurnedOff: "onboarding.step2.faceID"
        case .touchID: "onboarding.step2.touchID"
        case .opticID, .passcode: "onboarding.step2.passcode"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            step(1, "onboarding.step1")
            step(2, stepTwo)
            step(3, "onboarding.step3")
        }
        .padding(.top, 8)
    }

    private func step(_ number: Int, _ text: LocalizedStringResource) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(number, format: .number)
                .font(.subheadline.bold())
                .frame(width: 28, height: 28)
                .background(Color(.secondarySystemBackground), in: .circle)
            Text(text)
        }
    }
}
