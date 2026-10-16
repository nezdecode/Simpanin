//
//  TypePickerView.swift
//  Simpanin
//
//  Created by Inez Amanda on 16/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI
import VaultCore

/// "Jenis dokumen": the type decides the fields and the tile's colour. SIM goes on to its class.
struct TypePickerView: View {
    @Binding var selection: DocumentType
    @Environment(\.dismiss) private var dismiss

    private static let types: [DocumentType] = [.ktp, .passport, .stnk, .kk, .npwp, .bpjs, .other]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    typeRow(.ktp)
                    NavigationLink {
                        SIMClassList(selection: $selection, onPick: { dismiss() })
                    } label: {
                        LabeledContent {
                            if selection.isSIM { Text(DocumentStyle.name(selection)) }
                        } label: {
                            Text("typePicker.sim")
                        }
                    }
                    .accessibilityIdentifier("typePicker.sim")
                    ForEach(Self.types.dropFirst(), id: \.self) { typeRow($0) }
                } footer: {
                    Text("typePicker.footer")
                }
            }
            .navigationTitle(Text("review.type"))
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

    private func typeRow(_ type: DocumentType) -> some View {
        Button {
            selection = type
            dismiss()
        } label: {
            HStack {
                Text(DocumentStyle.name(type)).foregroundStyle(Color.primary)
                Spacer()
                if selection == type {
                    Image(systemName: "checkmark").foregroundStyle(.tint).accessibilityHidden(true)
                }
            }
        }
        .accessibilityAddTraits(selection == type ? .isSelected : [])
        .accessibilityIdentifier("typePicker.\(type.rawValue)")
    }
}

/// "Golongan SIM", Pribadi then Umum, as Perpol 5/2021 lists them. Each class is a document of its own.
private struct SIMClassList: View {
    @Binding var selection: DocumentType
    let onPick: () -> Void

    var body: some View {
        List {
            Section {
                ForEach(DocumentType.simClasses.prefix(8), id: \.self, content: row)
            } header: {
                Text("simClass.personal")
            }
            Section {
                ForEach(DocumentType.simClasses.dropFirst(8), id: \.self, content: row)
            } header: {
                Text("simClass.public")
            } footer: {
                Text("simClass.footer")
            }
        }
        .navigationTitle(Text("simClass.title"))
    }

    private func row(_ type: DocumentType) -> some View {
        Button {
            selection = type
            onPick()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(DocumentStyle.name(type)).foregroundStyle(Color.primary)
                    Text(LocalizedStringResource(String.LocalizationValue("simClass.description.\(type.rawValue)")))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if selection == type {
                    Image(systemName: "checkmark").foregroundStyle(.tint).accessibilityHidden(true)
                }
            }
        }
        .accessibilityAddTraits(selection == type ? .isSelected : [])
        .accessibilityIdentifier("typePicker.\(type.rawValue)")
    }
}
