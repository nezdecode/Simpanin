//
//  FormCopiesTests.swift
//  SimpaninTests
//
//  Created by Inez Amanda on 7/11/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Testing

@testable import Simpanin

/// What a form field's system Copy and Cut leave on the pasteboard. Synthetic values only; NIKs start with 00.
@MainActor
@Suite("Form copies")
struct FormCopiesTests {
    private static let nik = "0012341708900001"
    private static let values = [nik, "BUDI CONTOH", "17-08-1990"]

    /// A pasteboard in memory: the system's copy sets its text, and the app's clipboard writes over it, each
    /// counting as a change.
    final class Board: Clipboard {
        var text: String?
        var changeCount = 0
        private(set) var copied: [String] = []
        /// Runs inside each copy, like a change notice the system posts at once.
        var onCopy: (() -> Void)?

        func systemCopy(_ text: String?) {
            self.text = text
            changeCount += 1
        }

        func copy(_ text: String) {
            copied.append(text)
            systemCopy(text)
            onCopy?()
        }

        var pasteboard: FormCopies.Pasteboard {
            FormCopies.Pasteboard(text: { self.text }, changeCount: { self.changeCount })
        }
    }

    private func copies(_ board: Board) -> FormCopies {
        FormCopies(clipboard: board, pasteboard: board.pasteboard)
    }

    @Test func aCopiedNumberGoesThroughTheAppsClipboard() {
        let board = Board()
        let copies = copies(board)
        board.systemCopy(Self.nik)
        copies.pasteboardChanged(fieldValues: Self.values)
        #expect(board.copied == [Self.nik])
    }

    @Test func partOfAFieldCountsToo() {
        let board = Board()
        let copies = copies(board)
        board.systemCopy("1708")
        copies.pasteboardChanged(fieldValues: Self.values)
        #expect(board.copied == ["1708"])
    }

    @Test func textThatIsNoFieldsIsLeftAlone() {
        let board = Board()
        let copies = copies(board)
        // A single space is inside "BUDI CONTOH", but copying it copies nothing of the document.
        for text in ["Kantor", "", " ", "   ", nil] {
            board.systemCopy(text)
            copies.pasteboardChanged(fieldValues: Self.values)
        }
        #expect(board.copied.isEmpty)
    }

    @Test func anEmptyFieldMatchesNothing() {
        let board = Board()
        let copies = copies(board)
        board.systemCopy("Kantor")
        copies.pasteboardChanged(fieldValues: ["", Self.nik])
        #expect(board.copied.isEmpty)
    }

    /// The app's own write changes the pasteboard too; it isn't copied again.
    @Test func itsOwnWriteIsNotCopiedAgain() {
        let board = Board()
        let copies = copies(board)
        board.systemCopy(Self.nik)
        copies.pasteboardChanged(fieldValues: Self.values)
        copies.pasteboardChanged(fieldValues: Self.values)
        #expect(board.copied == [Self.nik])
    }

    /// A notice posted during the write itself doesn't start a second write.
    @Test func aNoticeDuringTheWriteIsIgnored() {
        let board = Board()
        let copies = copies(board)
        board.onCopy = { copies.pasteboardChanged(fieldValues: Self.values) }
        board.systemCopy(Self.nik)
        copies.pasteboardChanged(fieldValues: Self.values)
        #expect(board.copied == [Self.nik])
    }

    @Test func aSecondCopyIsMadeLocalToo() {
        let board = Board()
        let copies = copies(board)
        board.systemCopy(Self.nik)
        copies.pasteboardChanged(fieldValues: Self.values)
        board.systemCopy("BUDI")
        copies.pasteboardChanged(fieldValues: Self.values)
        #expect(board.copied == [Self.nik, "BUDI"])
    }
}
