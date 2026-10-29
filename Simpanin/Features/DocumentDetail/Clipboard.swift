//
//  Clipboard.swift
//  Simpanin
//
//  Created by Inez Amanda on 28/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import UIKit
import UniformTypeIdentifiers

/// Where a copied number or name goes, so tests can stand in for the system clipboard.
protocol Clipboard {
    func copy(_ text: String)
}

/// The system clipboard. A copy stays on this phone and is gone after 60 seconds; nothing clears it
/// earlier, so a paste into another app still works after the vault locks.
struct SystemClipboard: Clipboard {
    static let lifetime: TimeInterval = 60

    /// The pasteboard can't be read back in a test, so the write is passed in.
    let write: ([[String: Any]], [UIPasteboard.OptionsKey: Any]) -> Void
    let now: () -> Date

    init(
        write: @escaping ([[String: Any]], [UIPasteboard.OptionsKey: Any]) -> Void = {
            UIPasteboard.general.setItems($0, options: $1)
        },
        now: @escaping () -> Date = Date.init
    ) {
        self.write = write
        self.now = now
    }

    func copy(_ text: String) {
        write(
            [[UTType.utf8PlainText.identifier: text]],
            [.localOnly: true, .expirationDate: now().addingTimeInterval(Self.lifetime)])
    }
}
