//
//  WarningText.swift
//  Simpanin
//
//  Created by Inez Amanda on 17/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

/// Something to look at again, in amber with a triangle: "Periksa lagi" under a field, or a page of a scan
/// read as another document.
struct WarningText: View {
    let text: Text

    init(_ text: LocalizedStringResource) { self.text = Text(text) }

    /// A text already put together from the catalog, never looked up as a key.
    init(verbatim text: String) { self.text = Text(verbatim: text) }

    /// Warning is the ground of a notice card; text on a plain row needs its own colour to be read.
    static let color = ColorResource.onWarning

    var body: some View {
        Label {
            text
        } icon: {
            Image(systemName: "exclamationmark.triangle")
        }
        .font(.footnote)
        .foregroundStyle(Color(Self.color))
    }
}
