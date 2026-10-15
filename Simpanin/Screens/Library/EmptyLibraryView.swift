//
//  EmptyLibraryView.swift
//  Simpanin
//
//  Created by Inez Amanda on 14/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

/// "Belum ada dokumen".
struct EmptyLibraryView: View {
    var body: some View {
        VStack(spacing: 12) {
            IconBadge(
                systemImage: "lock.shield", size: 52, symbolFont: .system(size: 26), tint: Color(.onAccent),
                background: .accentColor)
            Text("empty.title").font(.title3.bold())
            Text("empty.body").foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(.vertical, 60)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("list.empty")
    }
}
