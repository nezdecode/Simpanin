//
//  PhotoLoadingView.swift
//  Simpanin
//
//  Created by Inez Amanda on 31/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

/// Shown while Photos hands over the photos added, instead of an empty Periksa data. Batal ends at once:
/// nothing has been read or typed yet, and the photos stay in Photos.
struct PhotoLoadingView: View {
    /// The photo being loaded, from 1, of how many.
    let number: Int
    let count: Int
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                ProgressView()
                text
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("photos.loading")
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: onCancel) { Text(ScreenText.cancel) }
                        .accessibilityIdentifier("photos.loadingCancel")
                }
            }
        }
        // VoiceOver says why the screen is waiting, as nothing else on it changes.
        .onAppear { AccessibilityNotification.Announcement(String(localized: "photos.loading")).post() }
    }

    /// One photo needs no count; with more, slow iCloud photos show the load is moving.
    private var text: Text {
        count > 1 ? Text("photos.loadingProgress \(number) \(count)") : Text("photos.loading")
    }
}
