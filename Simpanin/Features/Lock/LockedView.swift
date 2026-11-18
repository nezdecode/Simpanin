//
//  LockedView.swift
//  Simpanin
//
//  Created by Inez Amanda on 14/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

/// The dark cover with the app's name, and at its foot what `CoverContent` says: Buka, or a progress indicator
/// while a lock or an open that lost to one still runs. While the vault is open it never says
/// "Terkunci": only the name, or why it's hidden while the screen is recorded.
struct LockedView: View {
    let lock: LockController
    private let method = UnlockMethod.current()

    private var subtitle: LocalizedStringResource? {
        switch CoverContent(lock) {
        case .recording: "cover.recording"
        case .nameOnly: nil
        default: "lock.subtitle"
        }
    }

    private var openBlock: some View {
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
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 16) {
                IconBadge(
                    systemImage: "lock.shield", size: 88, symbolFont: .system(size: 44), tint: Color(.lockIcon),
                    background: Color(.lockIconBackground), outline: .roundedRectangle(cornerRadius: 22))
                Text("lock.title").font(.title.bold())
                    .accessibilityIdentifier("lock.title")
                if let subtitle {
                    Text(subtitle)
                        .foregroundStyle(Color(.lockSecondaryText))
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("lock.subtitle")
                }
            }
            .padding(.horizontal, 32)
            Spacer()
            if case .lockScreen(let action) = CoverContent(lock) {
                // Laid out even while held back, so the title above doesn't move as Buka comes and goes. Hidden,
                // not see-through, so neither a tap nor VoiceOver reaches it.
                Group {
                    if action == .open { openBlock } else { openBlock.hidden() }
                }
                // On Buka's row, not the middle of the block, which takes in the caption below it.
                .overlay(alignment: .top) {
                    if action == .waiting {
                        ProgressView()
                            .tint(.white)
                            .frame(minHeight: 54)
                            .accessibilityLabel(Text("lock.waiting"))
                            .accessibilityIdentifier("lock.waiting")
                    }
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
