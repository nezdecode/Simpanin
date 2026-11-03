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

/// "+": scan a document or pick photos of one. A phone without VisionKit's document camera can't scan, so
/// there "+" opens Photos without a menu of one item.
struct AddDocumentMenu: View {
    let hasCamera: Bool
    let isDisabled: Bool
    let onAdd: (ScanSource) -> Void

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
                    label
                }
            } else {
                Button {
                    onAdd(.photos)
                } label: {
                    label
                }
            }
        }
        .disabled(isDisabled)
        .accessibilityIdentifier("list.scan")
    }

    private var label: some View {
        Label {
            Text("main.add")
        } icon: {
            Image(systemName: "plus")
        }
    }
}
