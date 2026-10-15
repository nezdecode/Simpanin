//
//  AutoLockView.swift
//  Simpanin
//
//  Created by Inez Amanda on 15/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

/// "Kunci otomatis": how long Simpanin may stay open in the background. The choice lives in the
/// LockController, so this screen and the lock always agree.
struct AutoLockView: View {
    let lock: LockController

    var body: some View {
        Form {
            Section {
                ForEach(AutoLock.allCases, id: \.self) { choice in
                    Button {
                        lock.setAutoLock(choice)
                    } label: {
                        HStack {
                            Text(choice.title)
                            Spacer()
                            if lock.autoLock == choice {
                                Image(systemName: "checkmark")
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Color.accentColor)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                    // A button in a Form tints its whole label; the choices read as plain text,
                    // with only the checkmark in the accent colour.
                    .foregroundStyle(.primary)
                    .accessibilityAddTraits(lock.autoLock == choice ? .isSelected : [])
                    .accessibilityIdentifier("autoLock.\(choice.rawValue)")
                }
            } footer: {
                Text("autoLock.footer")
            }
        }
        .navigationTitle(Text("settings.autoLock"))
    }
}
