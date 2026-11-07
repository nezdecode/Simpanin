//
//  ReviewTextTests.swift
//  SimpaninTests
//
//  Created by Inez Amanda on 19/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import Parsers
import Testing
import VaultCore

@testable import Simpanin

@Suite("Review texts")
struct ReviewTextTests {
    /// Picked photos are never moved or deleted, so their texts say the originals stay in Photos; the
    /// camera's texts are unchanged.
    @Test func photosSayTheOriginalsStay() {
        #expect(String(localized: ReviewText.rescan(.photos)) == "Pilih foto lain")
        #expect(String(localized: ReviewText.rescan(.camera)) == "Pindai ulang")
        #expect(
            String(localized: ReviewText.rescanConfirm(.photos))
                == "Perubahan yang kamu buat akan diganti foto yang baru dipilih.")
        #expect(
            String(localized: ReviewText.rescanConfirm(.camera))
                == "Perubahan yang kamu buat akan diganti hasil pindaian baru.")
        #expect(String(localized: ReviewText.discardConfirm(.photos)) == "Buang tanpa menyimpan?")
        #expect(String(localized: ReviewText.discardConfirm(.camera)) == "Buang pindaian ini?")
        let discardMessage = ReviewText.discardMessage(.photos).map { String(localized: $0) }
        #expect(discardMessage == "Foto aslinya tetap ada di app Foto.")
        #expect(ReviewText.discardMessage(.camera) == nil)
        let footnote = ReviewText.pagesFootnote(.photos).map { String(localized: $0) }
        #expect(footnote == "Foto aslinya masih ada di app Foto.")
        #expect(ReviewText.pagesFootnote(.camera) == nil)
    }
}
