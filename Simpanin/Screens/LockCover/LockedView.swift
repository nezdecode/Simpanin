//
//  LockedView.swift
//  Simpanin
//
//  Created by Inez Amanda on 15/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

/// The dark cover with the app's name and the "Buka" button.
struct LockedView: View {
    let lock: LockController
    private let method = UnlockMethod.current()

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 16) {
                IconBadge(
                    systemImage: "lock.shield", size: 88, symbolFont: .system(size: 44), tint: Color(.lockIcon),
                    background: Color(.lockIconBackground), outline: .roundedRectangle(cornerRadius: 22))
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
                            Image(systemName: method.systemImage)
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
