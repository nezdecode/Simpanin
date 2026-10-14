//
//  DocumentStyleTests.swift
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

/// How a document's type reads on the list. Nothing here may need the document's encrypted
/// fields: the list only knows the type, the label and the expiry date.
@Suite("Document style")
struct DocumentStyleTests {
    static let names: [(DocumentType, String)] = [
        (.ktp, "KTP"), (.simA, "SIM A"), (.simB1, "SIM B1"), (.simB2, "SIM B2"), (.simC, "SIM C"),
        (.simD, "SIM D"), (.sim, "SIM"), (.passport, "Paspor"), (.stnk, "STNK"), (.kk, "Kartu Keluarga"),
        (.npwp, "NPWP"), (.bpjs, "BPJS"), (.other, "Lainnya"),
    ]

    @Test(arguments: names)
    func typeName(_ type: DocumentType, _ name: String) {
        #expect(String(localized: DocumentStyle.name(type)) == name)
    }

    @Test func nameWithLabel() {
        #expect(String(localized: DocumentStyle.name(.npwp, label: "Kantor")) == "NPWP · Kantor")
        #expect(String(localized: DocumentStyle.name(.ktp, label: nil)) == "KTP")
        #expect(String(localized: DocumentStyle.name(.ktp, label: "  ")) == "KTP")
    }

    @Test func aTypeFromANewerVersionReadsAsOther() {
        #expect(String(localized: DocumentStyle.name(DocumentType(rawValue: "visa"))) == "Lainnya")
    }

    /// Every type's tile colours have a dark variant. The asset symbols make sure they exist.
    @MainActor @Test(arguments: names.map(\.0))
    func tileColorsExist(_ type: DocumentType) {
        let colors = DocumentStyle.tileColors(type)
        for resource in [colors.background, colors.foreground] {
            let color = UIColor(resource: resource)
            let light = color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
            let dark = color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
            #expect(light != dark, "\(type.rawValue) has no dark variant")
        }
    }
}
