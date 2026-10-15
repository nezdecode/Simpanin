//
//  ScanModel.swift
//  Simpanin
//
//  Created by Inez Amanda on 15/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import CoreGraphics
import Observation
import Parsers
import VaultCore

/// One scan, from the camera's pages to what the parsers read. Kept in memory only, until it's saved
/// or dropped; when the vault locks it's dropped.
@MainActor @Observable
final class ScanModel {
    enum State: Equatable {
        case empty, reading, read, failed
    }

    private(set) var state = State.empty
    private(set) var pages: [CGImage] = []
    /// The recognised text, only for the DEBUG screen. Never logged or saved.
    private(set) var lines: [String] = []
    /// nil when the text isn't a document type the parsers know.
    private(set) var result: ParsedDocument?
    private(set) var method = RecognitionMethod.text

    private let recognizer: @Sendable (RecognitionMethod) -> any TextRecognizer
    private let today: @MainActor () -> CalendarDate

    init(
        recognizer: @escaping @Sendable (RecognitionMethod) -> any TextRecognizer = {
            VisionTextRecognizer(method: $0)
        },
        today: @escaping @MainActor () -> CalendarDate = { .today }
    ) {
        self.recognizer = recognizer
        self.today = today
    }

    /// Bumped by every read and every discard, so a read that finishes after either knows it's stale.
    private var generation = 0

    func scanned(_ pages: [CGImage]) async {
        self.pages = pages
        await read(using: method)
    }

    /// Reads the same pages again, for example with the other Vision request.
    func read(using method: RecognitionMethod) async {
        self.method = method
        generation += 1
        let run = generation
        state = .reading
        lines = []
        result = nil
        let recognizer = recognizer(method)
        let pages = pages
        do {
            var lines: [String] = []
            for page in pages {
                lines += try await recognizer.lines(in: page)
            }
            // The vault may have locked meanwhile; a stale read must not bring the scan back.
            guard run == generation else { return }
            self.lines = lines
            result = KTPParser.parse(lines, today: today()) ?? SIMParser.parse(lines, today: today())
            state = .read
        } catch {
            guard run == generation else { return }
            state = .failed
        }
    }

    func discard() {
        generation += 1
        pages = []
        lines = []
        result = nil
        state = .empty
    }
}
