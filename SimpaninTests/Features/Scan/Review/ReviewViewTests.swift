//
//  ReviewViewTests.swift
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
struct ReviewViewTests {
    /// The keys are built at run time, so Xcode can't see they're missing; a missing one shows its key.
    @Test func everyReasonHasACatalogText() {
        for reason in CheckReason.allCases {
            for number in [FieldKey.nik, FieldKey.simNumber] {
                let text = String(localized: ReviewView.reasonText(reason, numberKey: number))
                #expect(!text.hasPrefix("review."), "\(reason.rawValue), \(number)")
                #expect(text.hasSuffix("."), "\(reason.rawValue), \(number)")
            }
        }
        let other = String(localized: ReviewView.text(for: .dateFromAnotherType, numberKey: nil))
        #expect(other == "Periksa lagi: tanggal ini dibaca untuk jenis dokumen lain.")
    }

    /// Two reasons name the number that holds the birth date: the NIK on a KTP, the number on a SIM.
    @Test func theNIKAndNumberVariantsFollowTheDocument() {
        let ktp = String(localized: ReviewView.text(for: .mark(.disagreesWithBirthDate), numberKey: FieldKey.nik))
        #expect(ktp == "Periksa lagi: NIK dan tanggal lahir tidak cocok.")
        let sim = String(
            localized: ReviewView.text(for: .mark(.disagreesWithBirthDate), numberKey: FieldKey.simNumber))
        #expect(sim == "Periksa lagi: nomor dan tanggal lahir tidak cocok.")
    }

    @Test func aMarkWithoutAReasonIsPlain() {
        #expect(String(localized: ReviewView.text(for: .mark(nil), numberKey: nil)) == "Periksa lagi")
    }
}
