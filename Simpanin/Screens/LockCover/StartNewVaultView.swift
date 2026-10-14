//
//  StartNewVaultView.swift
//  Simpanin
//
//  Created by Inez Amanda on 15/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

/// "Mulai vault baru" with its typed confirmation.
struct StartNewVaultView: View {
    @State var model: StartNewVaultModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("startNew.explanation")
                    Text("startNew.instruction \(StartNewVaultModel.confirmationWord)")
                    TextField(StartNewVaultModel.confirmationWord, text: $model.typed)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("startNew.field")
                }
                if model.failed {
                    Text("startNew.failed").foregroundStyle(Color(.destructive))
                }
                Button {
                    Task {
                        await model.confirm()
                        if !model.failed { dismiss() }
                    }
                } label: {
                    Text(ScreenText.startNewVault)
                }
                .disabled(!model.canConfirm)
                .accessibilityIdentifier("startNew.confirm")
            }
            .navigationTitle(Text("startNew.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text(ScreenText.cancel)
                    }
                }
            }
        }
    }
}
