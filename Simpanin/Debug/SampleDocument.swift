//
//  SampleDocument.swift
//  Simpanin
//
//  Created by Inez Amanda on 14/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

#if DEBUG
    import UIKit
    import VaultCore

    /// A synthetic document for trying the screens without a scanner. Its numbers start with 00,
    /// a province code no real region has, so they can never be a real person's.
    struct SampleDocument {
        let type: DocumentType
        let label: String?
        let expiry: CalendarDate?
        let fields: DocumentFields
        let pages: [Data]

        /// In turn: a KTP, a SIM A with two pages, a passport, an older SIM C with a 14-digit number, and a KTP
        /// with no NIK. `expiringSoon` dates each a few days ahead, so UI tests see the expiry banner; a KTP has
        /// no date either way, as Periksa data saves it.
        init(number: Int, expiringSoon: Bool = false) {
            let kind = (number - 1) % 5
            type = [DocumentType.ktp, .simA, .passport, .simC, .ktp][kind]
            label = ["Saya", nil, nil, "Ibu", nil][kind]
            expiry =
                if type == .ktp {
                    nil
                } else if expiringSoon {
                    CalendarDate.day(of: .now.addingTimeInterval(Double(5 * number) * 86_400), in: .current)
                } else {
                    CalendarDate(year: 2030 + number % 5, month: 8, day: 17)
                }
            var values = [FieldKey.name: "CONTOH \(number)", FieldKey.birthDate: "1990-08-17"]
            switch kind {
            case 0: values[FieldKey.nik] = "00" + String(format: "%014d", number)
            case 1: values[FieldKey.simNumber] = "00" + String(format: "%014d", number)
            case 3: values[FieldKey.simNumber] = "00" + String(format: "%012d", number)
            default: break
            }
            fields = DocumentFields(values)
            pages = (1...(kind == 1 ? 2 : 1)).map { Self.pageImage(label: "CONTOH \(number) · \($0)") }
        }

        private static func pageImage(label: String) -> Data {
            let size = CGSize(width: 856, height: 540)
            let image = UIGraphicsImageRenderer(size: size).image { context in
                UIColor.systemTeal.setFill()
                context.fill(CGRect(origin: .zero, size: size))
                let text = NSAttributedString(
                    string: label,
                    attributes: [.font: UIFont.boldSystemFont(ofSize: 64), .foregroundColor: UIColor.white])
                text.draw(at: CGPoint(x: 48, y: 48))
            }
            return image.jpegData(compressionQuality: 0.8) ?? Data()
        }
    }
#endif
