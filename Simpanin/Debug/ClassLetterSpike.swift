//
//  ClassLetterSpike.swift
//  Simpanin
//
//  Created by Inez Amanda on 28/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

#if DEBUG
    import CoreGraphics
    import CoreText
    import Parsers
    import VaultCore
    import Vision

    /// DEBUG only. A spike: Vision drops the large lone "A" on an older SIM, so this re-reads only the area
    /// above the number line, where the class letter sits, in several ways, to see which one finds it.
    nonisolated enum ClassLetterSpike {
        enum Framing: Sendable {
            case tight
            /// The crop drawn in the middle of a white page four times its size, so the letter is
            /// ordinary text height there.
            case padded
            /// Padded, after shrinking the crop to 40 pixels high, so the letter is small in pixels too.
            case small
            /// Padded, with "KELAS" drawn left of the crop, so Vision sees a word rather than a lone letter.
            case word
        }

        struct Variant: Sendable {
            var name: String
            var level: RecognizeTextRequest.RecognitionLevel
            var framing: Framing
            /// Language correction on, with the class letters as custom words. Safe here: the crop holds
            /// no number for it to turn into a word.
            var hints = false
        }

        static let variants = [
            Variant(name: "1 accurate, tight", level: .accurate, framing: .tight),
            Variant(name: "2 accurate, padded", level: .accurate, framing: .padded),
            Variant(name: "3 fast, tight", level: .fast, framing: .tight),
            Variant(name: "4 fast, padded", level: .fast, framing: .padded),
            Variant(name: "5 accurate, padded, hints", level: .accurate, framing: .padded, hints: true),
            Variant(name: "6 accurate, small", level: .accurate, framing: .small),
            Variant(name: "7 accurate, beside KELAS", level: .accurate, framing: .word),
        ]

        /// Only the class each variant matched, never the crop's text: it can catch part of the title or name.
        enum Outcome: Sendable {
            case matched(DocumentType)
            case noClass
            case failed
        }

        enum Reading: Sendable {
            /// No observation was a SIM number on its own, though the parser, which joins a row's pieces
            /// and corrects lookalikes, may have found one.
            case noNumber
            case nothingAbove
            /// One outcome per variant, in order.
            case read(crop: CGImage, outcomes: [Outcome])
        }

        private static let languages = [Locale.Language(identifier: "id"), Locale.Language(identifier: "en")]

        @concurrent static func read(_ page: CGImage) async throws -> Reading {
            var request = RecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = languages
            request.usesLanguageCorrection = false
            let number = try await request.perform(on: page).first { observation in
                let text = observation.topCandidates(1).first?.string ?? ""
                return SIMParser.isWellFormedNumber(text.filter { $0 != "-" && $0 != " " })
            }
            guard let box = number?.boundingBox else { return .noNumber }
            guard
                let rect = cropRect(
                    aboveNumber: CGRect(x: box.origin.x, y: box.origin.y, width: box.width, height: box.height)),
                let crop = page.cropping(to: pixelRect(rect, width: page.width, height: page.height))
            else { return .nothingAbove }
            let framed: [Framing: CGImage] = [
                .tight: crop, .padded: padded(crop), .small: shrunk(crop).flatMap { padded($0) },
                .word: padded(crop, word: "KELAS"),
            ]
            .compactMapValues(\.self)
            var outcomes: [Outcome] = []
            for variant in variants {
                try Task.checkCancellation()
                // One variant failing (the fast level may not know Indonesian) leaves the others' answers.
                guard let image = framed[variant.framing],
                    let type = try? await simClass(in: image, using: variant)
                else {
                    outcomes.append(.failed)
                    continue
                }
                outcomes.append(type == .sim ? .noClass : .matched(type))
            }
            return .read(crop: crop, outcomes: outcomes)
        }

        /// The area above the number's box, in Vision's normalized coordinates (origin at the bottom left):
        /// four of its heights up, and one height wider on each side. nil when nothing is left above it.
        static func cropRect(aboveNumber box: CGRect) -> CGRect? {
            let above = CGRect(
                x: box.minX - box.height, y: box.maxY, width: box.width + 2 * box.height, height: 4 * box.height)
            let rect = above.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
            return rect.isNull || rect.height < 0.001 ? nil : rect
        }

        /// Pixels count from the top left, Vision's normalized coordinates from the bottom left.
        static func pixelRect(_ rect: CGRect, width: Int, height: Int) -> CGRect {
            let width = CGFloat(width)
            let height = CGFloat(height)
            return CGRect(
                x: rect.minX * width, y: (1 - rect.maxY) * height, width: rect.width * width,
                height: rect.height * height
            )
            .integral
        }

        private static func shrunk(_ crop: CGImage) -> CGImage? {
            let height = min(40, crop.height)
            let width = max(1, crop.width * height / max(1, crop.height))
            guard let context = context(width: width, height: height) else { return nil }
            context.interpolationQuality = .high
            context.draw(crop, in: CGRect(x: 0, y: 0, width: width, height: height))
            return context.makeImage()
        }

        private static func context(width: Int, height: Int) -> CGContext? {
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            context?.setFillColor(CGColor(gray: 1, alpha: 1))
            context?.fill(CGRect(x: 0, y: 0, width: width, height: height))
            return context
        }

        private static func padded(_ crop: CGImage, word: String? = nil) -> CGImage? {
            guard let context = context(width: crop.width * 4, height: crop.height * 4) else { return nil }
            if let word {
                // Half the band's height, about the letter's, ending just left of the crop.
                let size = CGFloat(crop.height) / 2
                let font = CTFontCreateWithName("Helvetica-Bold" as CFString, size, nil)
                let text = NSAttributedString(
                    string: word + " ",
                    attributes: [
                        NSAttributedString.Key(kCTFontAttributeName as String): font,
                        NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
                    ])
                let line = CTLineCreateWithAttributedString(text)
                let width = CTLineGetTypographicBounds(line, nil, nil, nil)
                context.setFillColor(CGColor(gray: 0, alpha: 1))
                context.textPosition = CGPoint(x: CGFloat(crop.width) * 1.5 - width, y: CGFloat(crop.height) * 1.75)
                CTLineDraw(line, context)
            }
            context.draw(
                crop,
                in: CGRect(
                    x: CGFloat(crop.width) * 1.5, y: CGFloat(crop.height) * 1.5, width: CGFloat(crop.width),
                    height: CGFloat(crop.height)))
            return context.makeImage()
        }

        /// `.sim` when no single class was matched.
        private static func simClass(in image: CGImage, using variant: Variant) async throws -> DocumentType {
            var request = RecognizeTextRequest()
            request.recognitionLevel = variant.level
            request.recognitionLanguages = languages
            request.usesLanguageCorrection = variant.hints
            if variant.hints { request.customWords = ["A", "B", "C", "D", "I", "UMUM"] }
            let lines = try await request.perform(on: image).compactMap { $0.topCandidates(1).first?.string }
            // The drawn word isn't part of the card. Only that way strips it, so the others read as the parser does.
            let card = variant.framing == .word ? lines.map { $0.uppercased().replacing("KELAS", with: "") } : lines
            return SIMParser.simClass(in: card[...]).type
        }
    }
#endif
