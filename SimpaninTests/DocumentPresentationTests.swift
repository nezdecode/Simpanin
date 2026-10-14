//
//  DocumentPresentationTests.swift
//  SimpaninTests
//
//  Created by Inez Amanda on 15/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import Testing
import UIKit
import VaultCore

@testable import Simpanin

/// How a document's type and expiry read on the list. Nothing here may need the document's
/// encrypted fields: the list only knows the type and the expiry date.
@Suite("Document presentation")
struct DocumentPresentationTests {
    static let names: [(DocumentType, String)] = [
        (.ktp, "KTP"), (.simA, "SIM A"), (.simB1, "SIM B1"), (.simB2, "SIM B2"), (.simC, "SIM C"),
        (.simD, "SIM D"), (.sim, "SIM"), (.passport, "Paspor"), (.stnk, "STNK"), (.kk, "Kartu Keluarga"),
        (.npwp, "NPWP"), (.bpjs, "BPJS"), (.other, "Lainnya"),
    ]

    @Test(arguments: names)
    func typeName(_ type: DocumentType, _ name: String) {
        #expect(String(localized: DocumentStyle.name(type)) == name)
    }

    @Test func aTypeFromANewerVersionReadsAsOther() {
        #expect(String(localized: DocumentStyle.name(DocumentType(rawValue: "visa"))) == "Lainnya")
    }

    /// Every type has a tile colour pair in the asset catalog, in light and dark.
    @Test(arguments: names.map(\.0))
    func tileColoursExist(_ type: DocumentType) {
        let colours = DocumentStyle.tileColours(type)
        for name in [colours.background, colours.foreground] {
            let colour = UIColor(named: name)
            #expect(colour != nil, "\(name)")
            let light = colour?.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
            let dark = colour?.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
            #expect(light != dark, "\(name) has no dark variant")
        }
    }

    // MARK: Expiry wording

    let today = CalendarDate(year: 2026, month: 10, day: 15)!

    func text(_ type: DocumentType, _ expiry: CalendarDate?) -> String {
        String(localized: ExpiryText.text(type: type, expiry: expiry, today: today))
    }

    @Test func noExpiry() {
        #expect(text(.ktp, nil) == "Seumur hidup")
        #expect(text(.kk, nil) == "Tanpa masa berlaku")
        #expect(text(.bpjs, nil) == "Tanpa masa berlaku")
    }

    @Test func validLongerThanSixtyDays() {
        #expect(text(.passport, CalendarDate(year: 2033, month: 8, day: 17)) == "Berlaku sampai 17 Agu 2033")
        #expect(text(.stnk, CalendarDate(year: 2027, month: 3, day: 3)) == "Pajak sampai 3 Mar 2027")
    }

    @Test func withinSixtyDays() {
        #expect(text(.simA, CalendarDate(year: 2026, month: 11, day: 29)) == "Habis dalam 45 hari")
        #expect(text(.simA, CalendarDate(year: 2026, month: 12, day: 14)) == "Habis dalam 60 hari")
        #expect(text(.simA, today) == "Habis hari ini")
        #expect(text(.stnk, CalendarDate(year: 2026, month: 11, day: 29)) == "Pajak habis dalam 45 hari")
    }

    @Test func pastExpiry() {
        #expect(text(.simA, CalendarDate(year: 2026, month: 3, day: 3)) == "Sudah habis sejak 3 Mar")
        #expect(text(.simA, CalendarDate(year: 2025, month: 3, day: 3)) == "Sudah habis sejak 3 Mar 2025")
        #expect(text(.stnk, CalendarDate(year: 2026, month: 10, day: 14)) == "Pajak sudah habis sejak 14 Okt")
    }

    /// The banner on the list: documents that expire within 60 days or already have, soonest first.
    @Test func expiringSoonestFirst() {
        let soon = CalendarDate(year: 2026, month: 11, day: 1)!
        let later = CalendarDate(year: 2026, month: 12, day: 1)!
        let far = CalendarDate(year: 2030, month: 1, day: 1)!
        let past = CalendarDate(year: 2026, month: 1, day: 1)!
        // Indices into the input, past expiry first, then the soonest. Far and no expiry stay out.
        #expect(ExpiryText.needsAttention([later, nil, far, soon, past], today: today) == [4, 3, 0])
    }
}
