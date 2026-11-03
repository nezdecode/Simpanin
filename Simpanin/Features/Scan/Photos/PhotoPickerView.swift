//
//  PhotoPickerView.swift
//  Simpanin
//
//  Created by Inez Amanda on 31/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import PhotosUI
import SwiftUI

/// "Pilih foto": the system picker inside our own bar, so Tambah is the one way to confirm. Simpanin gets
/// only the photos added, without access to the library.
struct PhotoPickerView: View {
    @Binding var selection: [PhotosPickerItem]
    let onCancel: () -> Void
    let onAdd: () -> Void

    /// The pages of one document.
    static let maxCount = 5

    var body: some View {
        NavigationStack {
            // Never `photoLibrary: .shared()`: that would give the items an identifier into the library.
            PhotosPicker(
                selection: $selection, maxSelectionCount: Self.maxCount, selectionBehavior: .continuousAndOrdered,
                matching: .images, preferredItemEncoding: .current
            ) {
                EmptyView()
            }
            .photosPickerStyle(.inline)
            // Search and Collections stay, to find a card among many photos; the picker's own Done doesn't.
            .photosPickerDisabledCapabilities(.selectionActions)
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle(Text("photos.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: onCancel) { Text(ScreenText.cancel) }
                        .accessibilityIdentifier("photos.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: onAdd) { Text("photos.add \(selection.count)") }
                        .disabled(selection.isEmpty)
                        .accessibilityIdentifier("photos.add")
                }
            }
        }
    }
}
