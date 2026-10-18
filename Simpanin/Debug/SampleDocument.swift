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

    /// A synthetic document for trying the screens without a scanner. The NIK starts with 00,
    /// a province code no real region has, so it can never be a real person's number.
    struct SampleDocument {
        let type: DocumentType
        let label: String?
        let expiry: CalendarDate?
        let fields: DocumentFields
        let page: Data

        /// `expiringSoon` dates each sample a few days ahead, so UI tests see the expiry banner.
        init(number: Int, expiringSoon: Bool = false) {
            let types: [DocumentType] = [.ktp, .sim, .passport]
            type = types[(number - 1) % types.count]
            let labels = ["Saya", nil, nil, "Ibu"]
            label = labels[(number - 1) % labels.count]
            expiry =
                expiringSoon
                ? CalendarDate.day(of: .now.addingTimeInterval(Double(5 * number) * 86_400), in: .current)
                : CalendarDate(year: 2030 + number % 5, month: 8, day: 17)
            fields = DocumentFields([
                FieldKey.nik: "00" + String(format: "%014d", number),
                FieldKey.name: "CONTOH \(number)",
            ])
            page = Self.pageImage(label: "CONTOH \(number)")
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
