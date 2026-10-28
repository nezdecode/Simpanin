//
//  DocumentFieldStyleTests.swift
//  SimpaninTests
//
//  Created by Inez Amanda on 28/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import Testing
import VaultCore

@testable import Simpanin

/// Periksa data and the document screen both read their fields from here, so they never disagree.
@Suite("Document field style")
struct DocumentFieldStyleTests {
    /// Every SIM class has the same fields as the classless SIM; types without a parser have none yet.
    @Test func fieldKeysPerType() {
        #expect(DocumentFieldStyle.keys(for: .ktp) == [FieldKey.nik, FieldKey.name, FieldKey.birthDate])
        for type in DocumentType.simClasses + [.sim] {
            #expect(
                DocumentFieldStyle.keys(for: type) == [FieldKey.simNumber, FieldKey.name, FieldKey.birthDate],
                "\(type.rawValue)")
        }
        let withoutFields: [DocumentType] = [
            .passport, .stnk, .kk, .npwp, .bpjs, .other, DocumentType(rawValue: "visa"),
        ]
        for type in withoutFields {
            #expect(DocumentFieldStyle.keys(for: type).isEmpty, "\(type.rawValue)")
        }
    }

    @Test(arguments: [
        (FieldKey.nik, "NIK"), (FieldKey.simNumber, "Nomor SIM"), (FieldKey.name, "Nama"),
        (FieldKey.birthDate, "Tanggal lahir"),
    ])
    func titlePerKey(_ key: String, _ title: String) {
        #expect(String(localized: DocumentFieldStyle.title(for: key)) == title)
    }

    @Test func validityTitlePerType() {
        #expect(String(localized: DocumentFieldStyle.validityTitle(for: .stnk)) == "Pajak berlaku sampai")
        for type in [DocumentType.ktp, .simA, .sim, .passport, .kk, .npwp, .bpjs, .other] {
            #expect(
                String(localized: DocumentFieldStyle.validityTitle(for: type)) == "Berlaku sampai", "\(type.rawValue)")
        }
    }
}
