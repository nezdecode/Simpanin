//
//  AddDocumentMenu.swift
//  Simpanin
//
//  Created by Inez Amanda on 31/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

/// "+", and the empty list's "Tambah dokumen": scan a document or pick photos of one. A phone without
/// VisionKit's document camera can't scan, so there it opens Photos without a menu of one item.
struct AddDocumentMenu<Title: View>: View {
    let hasCamera: Bool
    let isDisabled: Bool
    var identifier = "list.scan"
    let onAdd: (ScanSource) -> Void
    @ViewBuilder let title: () -> Title

    var body: some View {
        Group {
            if hasCamera {
                Menu {
                    Button {
                        onAdd(.camera)
                    } label: {
                        Label {
                            Text("main.scan")
                        } icon: {
                            Image(systemName: "camera")
                        }
                    }
                    .accessibilityIdentifier("list.scan.camera")
                    Button {
                        onAdd(.photos)
                    } label: {
                        Label {
                            Text("main.pickPhotos")
                        } icon: {
                            Image(systemName: "photo.on.rectangle")
                        }
                    }
                    .accessibilityIdentifier("list.scan.photos")
                } label: {
                    title()
                }
            } else {
                Button {
                    onAdd(.photos)
                } label: {
                    title()
                }
            }
        }
        .disabled(isDisabled)
        .accessibilityIdentifier(identifier)
    }
}

extension AddDocumentMenu where Title == Label<Text, Image> {
    /// The toolbar's "+".
    init(hasCamera: Bool, isDisabled: Bool, onAdd: @escaping (ScanSource) -> Void) {
        self.init(hasCamera: hasCamera, isDisabled: isDisabled, onAdd: onAdd) {
            Label {
                Text("main.add")
            } icon: {
                Image(systemName: "plus")
            }
        }
    }
}
