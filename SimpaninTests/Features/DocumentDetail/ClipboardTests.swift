//
//  ClipboardTests.swift
//  SimpaninTests
//
//  Created by Inez Amanda on 28/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import Testing
import UIKit
import UniformTypeIdentifiers

@testable import Simpanin

@MainActor
@Suite("Clipboard")
struct ClipboardTests {
    /// Local-only keeps it off the user's other devices; the expiry takes it off this one.
    @Test func copyIsLocalOnlyAndExpiresInSixtySeconds() throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        var items: [[String: Any]] = []
        var options: [UIPasteboard.OptionsKey: Any] = [:]
        let clipboard = SystemClipboard(
            write: {
                items = $0
                options = $1
            }, now: { now })
        clipboard.copy("0012341708900001")
        #expect(items.count == 1)
        #expect(items.first?[UTType.utf8PlainText.identifier] as? String == "0012341708900001")
        #expect(options[.localOnly] as? Bool == true)
        #expect(options[.expirationDate] as? Date == now.addingTimeInterval(60))
        #expect(options.count == 2)
    }
}
