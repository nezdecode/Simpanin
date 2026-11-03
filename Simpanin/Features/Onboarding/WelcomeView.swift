//
//  WelcomeView.swift
//  Simpanin
//
//  Created by Inez Amanda on 3/11/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

/// The first screen on a phone with no vault yet: what Simpanin promises, then straight to the first
/// document. Each choice creates the vault, so nothing exists on the phone before one is made.
struct WelcomeView: View {
    let lock: LockController
    private let method = UnlockMethod.current()
    private let hasCamera = DocumentCamera.isAvailable
    @ScaledMetric(relativeTo: .body) private var pointIconSize = 32
    @AccessibilityFocusState private var titleFocused: Bool

    var body: some View {
        // The buttons stay reachable at any text size; the points scroll above them, and are read first.
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    IconBadge(
                        systemImage: "checkmark.shield", size: 72, symbolFont: .system(size: 34), tint: .accentColor,
                        background: Color(.accentSoft))
                    Text("welcome.title")
                        .font(.title.bold())
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityFocused($titleFocused)
                        .accessibilityIdentifier("welcome.title")
                    VStack(alignment: .leading, spacing: 20) {
                        point(WelcomeText.lockLine(for: method), systemImage: "lock")
                        point("privacy.noAccount", systemImage: "person.slash")
                        point("privacy.deviceOnly", systemImage: "iphone")
                    }
                    .padding(.top, 16)
                }
                .padding(.horizontal, 28)
                .padding(.top, 72)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            actions
        }
        .background(Color(.systemBackground))
        .onAppear { titleFocused = true }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            if hasCamera {
                choice("main.scan", systemImage: "camera", scan: .camera, emphasis: .primary)
                    .accessibilityIdentifier("welcome.scan")
                choice("main.pickPhotos", systemImage: "photo.on.rectangle", scan: .photos, emphasis: .secondary)
                    .accessibilityIdentifier("welcome.photos")
            } else {
                choice("main.pickPhotos", systemImage: "photo.on.rectangle", scan: .photos, emphasis: .primary)
                    .accessibilityIdentifier("welcome.photos")
            }
            Button {
                Task { await lock.createVault(then: nil) }
            } label: {
                Text("welcome.later").frame(maxWidth: .infinity, minHeight: 44)
            }
            .accessibilityIdentifier("welcome.later")
        }
        .disabled(lock.isCreatingVault)
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(Color(.systemBackground))
    }

    private func choice(
        _ title: LocalizedStringResource, systemImage: String, scan: ScanSource,
        emphasis: ProminentButtonStyle.Emphasis
    ) -> some View {
        Button {
            Task { await lock.createVault(then: scan) }
        } label: {
            Label {
                Text(title)
            } icon: {
                Image(systemName: systemImage)
            }
        }
        .buttonStyle(.prominent(emphasis))
    }

    private func point(_ text: LocalizedStringResource, systemImage: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Image(systemName: systemImage)
                .foregroundStyle(.tint)
                .frame(width: pointIconSize, height: pointIconSize)
                .background(Color(.secondarySystemBackground), in: .circle)
                .accessibilityHidden(true)
            Text(text)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
