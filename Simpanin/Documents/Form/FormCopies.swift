//
//  FormCopies.swift
//  Simpanin
//
//  Created by Inez Amanda on 7/11/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Combine
import SwiftUI
import UIKit

/// The system's Copy and Cut on a form field put the text on the general pasteboard, where it can reach other
/// devices and stays. SwiftUI can't take them out of a field's menu, so what the form's fields copy is copied
/// again through the app's clipboard: on this phone only, gone after a minute.
@MainActor
final class FormCopies {
    /// The general pasteboard's text and change count, read without asking: the app put it there itself.
    struct Pasteboard {
        let text: () -> String?
        let changeCount: () -> Int

        static let general = Pasteboard(
            text: { UIPasteboard.general.string }, changeCount: { UIPasteboard.general.changeCount })
    }

    private let clipboard: any Clipboard
    private let pasteboard: Pasteboard
    /// The change count after the app's own write, which changes the pasteboard too.
    private var ownChange: Int?
    /// The write is under way; a change notice can come before it returns.
    private var writing = false

    init(clipboard: any Clipboard = SystemClipboard(), pasteboard: Pasteboard = .general) {
        self.clipboard = clipboard
        self.pasteboard = pasteboard
    }

    /// The pasteboard changed while one of the form's fields had focus.
    func pasteboardChanged(fieldValues: [String]) {
        guard !writing, pasteboard.changeCount() != ownChange, let text = pasteboard.text(),
            Self.isFromAField(text, fieldValues)
        else { return }
        writing = true
        defer { writing = false }
        clipboard.copy(text)
        ownChange = pasteboard.changeCount()
    }

    /// Text copied from a field is part of its value; anything else on the pasteboard isn't the form's.
    nonisolated static func isFromAField(_ text: String, _ fieldValues: [String]) -> Bool {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return fieldValues.contains { $0.contains(text) }
    }
}

extension View {
    /// While one of the form's fields has focus, what its Copy and Cut put on the pasteboard stays on this phone
    /// and expires, as `FormCopies` says.
    func keepsFieldCopiesLocal(_ fieldValues: [String], whileEditing editing: Bool) -> some View {
        modifier(FieldCopies(fieldValues: fieldValues, editing: editing))
    }
}

private struct FieldCopies: ViewModifier {
    let fieldValues: [String]
    let editing: Bool
    @State private var copies = FormCopies()

    func body(content: Content) -> some View {
        content.onReceive(NotificationCenter.default.publisher(for: UIPasteboard.changedNotification)) { _ in
            // Only a focused field has Copy and Cut; anything else on the pasteboard isn't read.
            if editing { copies.pasteboardChanged(fieldValues: fieldValues) }
        }
    }
}
