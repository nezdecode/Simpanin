//
//  MaskedTextTests.swift
//  SimpaninTests
//
//  Created by Inez Amanda on 16/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Testing

@testable import Simpanin

/// Synthetic values only.
@Suite("Masked text")
struct MaskedTextTests {
    @Test func valuesAreMaskedAndLabelsStay() {
        let lines = ["NIK : 0012341708900001", "Nama : BUDI CONTOH", "Tempat/Tgl Lahir : JAKARTA, 17-08-1990"]
        #expect(
            MaskedText.mask(lines)
                == "NIK : 9999999999999999\nNama : AAAA AAAAAA\nTempat/Tgl Lahir : AAAAAAA, 99-99-9999")
    }

    /// The point is to see what recognition read, so a misread label stays as it was read.
    @Test func aMisreadLabelStaysVisible() {
        #expect(MaskedText.mask(["Tempat/Tgi Lahir"]) == "Tempat/Tgi Lahir")
        #expect(MaskedText.mask(["NlK"]) == "NlK")
    }

    @Test func lowercaseLettersStayLowercase() {
        #expect(MaskedText.mask(["Budi c0ntoh"]) == "Aaaa a9aaaa")
    }

    /// SIM labels are bilingual; both halves stay.
    @Test func simLabelsStay() {
        #expect(MaskedText.mask(["Nama/Name", "Jenis Kelamin/Sex", "PRIA"]) == "Nama/Name\nJenis Kelamin/Sex\nAAAA")
    }
}
