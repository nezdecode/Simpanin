//
//  ContentView.swift
//  Simpanin
//
//  Created by Inez Amanda on 4/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

struct ContentView: View {
    /// Nil when the vault couldn't be set up, for example without the App Group entitlement.
    let vault: AppVault?

    var body: some View {
        NavigationStack {
            VStack {
                Image(systemName: "globe")
                    .imageScale(.large)
                    .foregroundStyle(.tint)
                Text("Hello, world!")
                #if DEBUG
                    NavigationLink("Device checks") { DeviceChecksView(vault: vault) }
                        .padding(.top)
                #endif
            }
            .padding()
        }
    }
}

#Preview {
    ContentView(vault: .preview())
}
