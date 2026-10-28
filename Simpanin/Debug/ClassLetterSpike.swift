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
    import Parsers
    import VaultCore
    import Vision

    /// DEBUG only. A spike: Vision drops the large lone "A" on an older SIM, so this re-reads only the area
    /// above the number line, where the class letter sits, in several ways, to see which one finds it.
    nonisolated enum ClassLetterSpike {
        struct Variant: Sendable {
            var name: String
            var level: RecognizeTextRequest.RecognitionLevel
            /// The crop drawn in the middle of a white page four times its size, so the letter is
            /// ordinary text height there.
            var padded: Bool
            /// Language correction on, with the class letters as custom words. Safe here: the crop holds
            /// no number for it to turn into a word.
            var hints: Bool
        }

        static let variants = [
            Variant(name: "1 accurate, tight", level: .accurate, padded: false, hints: false),
            Variant(name: "2 accurate, padded", level: .accurate, padded: true, hints: false),
            Variant(name: "3 fast, tight", level: .fast, padded: false, hints: false),
            Variant(name: "4 fast, padded", level: .fast, padded: true, hints: false),
            Variant(name: "5 accurate, padded, hints", level: .accurate, padded: true, hints: true),
        ]

        /// Only the class each variant matched, never the crop's text: it can catch part of the title or name.
        struct Reading: Sendable {
            var crop: CGImage
            /// nil where a variant matched no single class.
            var classes: [DocumentType?]
        }

        private static let languages = [Locale.Language(identifier: "id"), Locale.Language(identifier: "en")]

        /// nil when the page has no SIM number line or nothing above it.
        @concurrent static func read(_ page: CGImage) async throws -> Reading? {
            var request = RecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = languages
            request.usesLanguageCorrection = false
            let number = try await request.perform(on: page).first { observation in
                let text = observation.topCandidates(1).first?.string ?? ""
                return SIMParser.isWellFormedNumber(text.filter { $0 != "-" && $0 != " " })
            }
            guard let box = number?.boundingBox,
                let rect = cropRect(
                    aboveNumber: CGRect(x: box.origin.x, y: box.origin.y, width: box.width, height: box.height)),
                let crop = page.cropping(to: pixelRect(rect, in: page))
            else { return nil }
            var classes: [DocumentType?] = []
            for variant in variants {
                guard let image = variant.padded ? padded(crop) : crop else {
                    classes.append(nil)
                    continue
                }
                classes.append(try await simClass(in: image, using: variant))
            }
            return Reading(crop: crop, classes: classes)
        }

        /// The area above the number's box, in Vision's normalized coordinates (origin at the bottom left):
        /// four of its heights up, and one height wider on each side. nil when nothing is left above it.
        static func cropRect(aboveNumber box: CGRect) -> CGRect? {
            let above = CGRect(
                x: box.minX - box.height, y: box.maxY, width: box.width + 2 * box.height, height: 4 * box.height)
            let rect = above.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
            return rect.isNull || rect.height < 0.001 ? nil : rect
        }

        /// Pixels count from the top left.
        private static func pixelRect(_ rect: CGRect, in image: CGImage) -> CGRect {
            let width = CGFloat(image.width)
            let height = CGFloat(image.height)
            return CGRect(
                x: rect.minX * width, y: (1 - rect.maxY) * height, width: rect.width * width,
                height: rect.height * height
            )
            .integral
        }

        private static func padded(_ crop: CGImage) -> CGImage? {
            let width = crop.width * 4
            let height = crop.height * 4
            guard
                let context = CGContext(
                    data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return nil }
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.draw(
                crop,
                in: CGRect(
                    x: CGFloat(crop.width) * 1.5, y: CGFloat(crop.height) * 1.5, width: CGFloat(crop.width),
                    height: CGFloat(crop.height)))
            return context.makeImage()
        }

        private static func simClass(in image: CGImage, using variant: Variant) async throws -> DocumentType? {
            var request = RecognizeTextRequest()
            request.recognitionLevel = variant.level
            request.recognitionLanguages = languages
            request.usesLanguageCorrection = variant.hints
            if variant.hints { request.customWords = ["A", "B", "C", "D", "I", "UMUM"] }
            let lines = try await request.perform(on: image).compactMap { $0.topCandidates(1).first?.string }
            let type = SIMParser.simClass(in: lines[...]).type
            return type == .sim ? nil : type
        }
    }
#endif
