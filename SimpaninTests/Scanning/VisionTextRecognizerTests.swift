//
//  VisionTextRecognizerTests.swift
//  SimpaninTests
//
//  Created by Inez Amanda on 15/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import CoreGraphics
import Parsers
import Testing
import UIKit
import VaultCore

@testable import Simpanin

/// Runs real Vision on a page the test draws itself, so no image file is needed. Synthetic values only.
@Suite("Vision text recognizer")
struct VisionTextRecognizerTests {
    static let today = CalendarDate(year: 2026, month: 10, day: 15)!

    /// A plain KTP-like page: black text on white, one printed line per line.
    static func syntheticKTP() throws -> CGImage {
        let lines = [
            "PROVINSI DKI JAKARTA", "KOTA JAKARTA SELATAN", "NIK : 0012341708900001", "Nama : BUDI CONTOH",
            "Tempat/Tgl Lahir : JAKARTA, 17-08-1990", "Jenis Kelamin : LAKI-LAKI",
        ]
        let size = CGSize(width: 1200, height: 760)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 44, weight: .semibold), .foregroundColor: UIColor.black,
            ]
            for (index, line) in lines.enumerated() {
                (line as NSString).draw(at: CGPoint(x: 40, y: 40 + CGFloat(index) * 110), withAttributes: attributes)
            }
        }
        return try #require(image.cgImage)
    }

    @Test(arguments: RecognitionMethod.allCases)
    func readsASyntheticKTP(method: RecognitionMethod) async throws {
        let lines = try await VisionTextRecognizer(method: method).lines(in: Self.syntheticKTP())
        let ktp = try #require(KTPParser.parse(lines, today: Self.today), "\(method)")
        #expect(ktp.fields.values[FieldKey.nik] == "0012341708900001", "\(method)")
        #expect(ktp.fields.values[FieldKey.name] == "BUDI CONTOH", "\(method)")
    }
}
