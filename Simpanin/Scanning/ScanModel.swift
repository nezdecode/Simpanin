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
import OSLog
import Observation
import Parsers
import VaultCore

/// One scan, from the camera's pages to what the parsers read. Kept in memory only, until it's saved
/// or dropped. Start reads from the screen's `.task`, so a read is cancelled, and the scan dropped, when
/// the screen goes away, also when locking the vault removes it.
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
                // A dropped scan reads no further pages: they'd keep its pages in memory and Vision busy.
                guard run == generation else { return }
                // Cancelled with the screen that started it: locking the vault removes that screen before
                // it can drop the scan, so the read drops it.
                guard !Task.isCancelled else { return discard() }
                lines += try await recognizer.lines(in: page)
            }
            // The vault may have locked meanwhile; a stale or cancelled read must not bring the scan back.
            guard run == generation else { return }
            guard !Task.isCancelled else { return discard() }
            self.lines = lines
            result = KTPParser.parse(lines, today: today()) ?? SIMParser.parse(lines, today: today())
            state = .read
        } catch {
            guard run == generation else { return }
            // Vision may throw when its task is cancelled; that's a dropped scan, not a failure.
            guard !Task.isCancelled else { return discard() }
            Logger.scan.error("Recognition failed: \(ErrorSummary.describe(error), privacy: .public)")
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
