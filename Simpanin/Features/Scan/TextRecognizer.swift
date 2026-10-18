//
//  TextRecognizer.swift
//  Simpanin
//
//  Created by Inez Amanda on 15/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import CoreGraphics
import Vision

/// Reads the text on a scanned page, as lines in reading order. Tests use a stand-in.
nonisolated protocol TextRecognizer: Sendable {
    func lines(in page: CGImage) async throws -> [String]
}

/// Which Vision request reads the page. "Coba pindai" can run either on the same scan to compare them.
nonisolated enum RecognitionMethod: String, CaseIterable, Sendable {
    /// `RecognizeTextRequest`: the text as lines.
    case text
    /// `RecognizeDocumentsRequest` (iOS 26): the page as a document, with its structure.
    case document
}

nonisolated struct VisionTextRecognizer: TextRecognizer {
    var method = RecognitionMethod.text

    private static let languages = [Locale.Language(identifier: "id"), Locale.Language(identifier: "en")]

    /// `@concurrent` so recognition never runs on the main actor, whoever calls it.
    @concurrent func lines(in page: CGImage) async throws -> [String] {
        let observations: [RecognizedTextObservation]
        switch method {
        case .text:
            var request = RecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = Self.languages
            // Language correction would turn a NIK or a number into a word.
            request.usesLanguageCorrection = false
            observations = try await request.perform(on: page)
        case .document:
            var request = RecognizeDocumentsRequest()
            request.textRecognitionOptions.recognitionLanguages = Self.languages
            request.textRecognitionOptions.useLanguageCorrection = false
            observations = try await request.perform(on: page).flatMap(\.document.text.lines)
        }
        let pieces = observations.compactMap { observation in
            observation.topCandidates(1).first.map { candidate in
                let box = observation.boundingBox
                return TextPiece(
                    text: candidate.string,
                    box: CGRect(x: box.origin.x, y: box.origin.y, width: box.width, height: box.height))
            }
        }
        return ReadingOrder.lines(pieces)
    }
}
