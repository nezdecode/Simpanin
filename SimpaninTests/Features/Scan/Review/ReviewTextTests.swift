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
    /// The keys are built at run time, so Xcode can't see they're missing; a missing one shows its key.
    @Test func everyReasonHasACatalogText() {
        for reason in CheckReason.allCases {
            for number in [FieldKey.nik, FieldKey.simNumber] {
                let text = String(localized: ReviewText.reasonText(reason, numberKey: number))
                #expect(!text.hasPrefix("review."), "\(reason.rawValue), \(number)")
                #expect(text.hasSuffix("."), "\(reason.rawValue), \(number)")
            }
        }
        let other = String(localized: ReviewText.text(for: .dateFromAnotherType, numberKey: nil))
        #expect(other == "Periksa lagi: tanggal ini dibaca untuk jenis dokumen lain.")
    }

    /// The SIM title is built from a key with the class name as its argument, so a slip would show the key.
    @Test func theDuplicateTitleNamesTheType() {
        #expect(String(localized: ReviewText.duplicateTitle(.ktp)) == "Kamu sudah punya KTP dengan NIK ini.")
        #expect(String(localized: ReviewText.duplicateTitle(.simA)) == "Kamu sudah punya SIM A dengan nomor ini.")
        #expect(String(localized: ReviewText.duplicateTitle(.sim)) == "Kamu sudah punya SIM dengan nomor ini.")
    }

    /// Two reasons name the number that holds the birth date: the NIK on a KTP, the number on a SIM.
    @Test func theNIKAndNumberVariantsFollowTheDocument() {
        let ktp = String(localized: ReviewText.text(for: .mark(.disagreesWithBirthDate), numberKey: FieldKey.nik))
        #expect(ktp == "Periksa lagi: NIK dan tanggal lahir tidak cocok.")
        let sim = String(
            localized: ReviewText.text(for: .mark(.disagreesWithBirthDate), numberKey: FieldKey.simNumber))
        #expect(sim == "Periksa lagi: nomor dan tanggal lahir tidak cocok.")
        let sex = String(localized: ReviewText.text(for: .mark(.sexDisagrees), numberKey: FieldKey.simNumber))
        #expect(sex == "Periksa lagi: jenis kelamin tidak cocok dengan nomor SIM.")
    }

    /// On the type, a lookalike is a SIM class read with a 1 for an I.
    @Test func aLookalikeOnTheTypeSpeaksOfTheClass() {
        let type = String(localized: ReviewText.text(for: .mark(.lookalike), numberKey: nil, onType: true))
        #expect(type == "Periksa lagi: golongan terbaca kurang jelas.")
        let field = String(localized: ReviewText.text(for: .mark(.lookalike), numberKey: FieldKey.nik))
        #expect(field == "Periksa lagi: ada huruf yang terbaca mirip angka.")
    }

    @Test func severalDatesDontClaimEitherIsTheExpiry() {
        let text = String(localized: ReviewText.text(for: .mark(.severalDates), numberKey: nil))
        #expect(text == "Periksa lagi: beberapa tanggal terbaca, belum jelas mana tanggal habisnya.")
    }

    @Test func aMarkWithoutAReasonIsPlain() {
        #expect(String(localized: ReviewText.text(for: .mark(nil), numberKey: nil)) == "Periksa lagi")
    }
}
