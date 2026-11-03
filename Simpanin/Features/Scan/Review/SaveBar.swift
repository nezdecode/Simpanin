//
//  SaveBar.swift
//  Simpanin
//
//  Created by Inez Amanda on 31/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

/// "Simpan ke vault" under Periksa data. Preparing photos for the vault takes a few seconds, so while a
/// save runs it says "Menyimpan…".
struct SaveBar: View {
    let saving: Bool
    let isDisabled: Bool
    let onSave: () -> Void

    var body: some View {
        Button(action: onSave) {
            if saving {
                HStack(spacing: 8) {
                    ProgressView().tint(Color(.onAccent))
                    Text("review.saving")
                }
            } else {
                Text("review.save")
            }
        }
        .buttonStyle(.prominent)
        // Not disabled while saving: a disabled button turns see-through and "Menyimpan…" can't be read over
        // the form. The screen ignores taps while it saves.
        .disabled(isDisabled)
        .padding(16)
        .accessibilityIdentifier("review.save")
    }
}
