//
//  SharePurposeTests.swift
//  SimpaninTests
//
//  Created by Inez Amanda on 4/11/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import Testing

@testable import Simpanin

@Suite("Share purpose")
struct SharePurposeTests {
    @Test func aPurposeOfOnlySpacesCannotBeShared() {
        #expect(!SharePurpose.canShare(""))
        #expect(!SharePurpose.canShare("  \n\t "))
        #expect(SharePurpose.canShare(" a "))
    }

    @Test func newlinesAndControlCharactersAreRemoved() {
        #expect(SharePurpose.cleaned("Sewa\nkos\tJl.\u{0007} Perintis") == "Sewa kos Jl. Perintis")
        #expect(SharePurpose.cleaned("Bank\u{200B}\r\nBCA") == "Bank BCA")
    }

    @Test func spacesCollapseAndTrim() {
        #expect(SharePurpose.cleaned("   Sewa    kos  ") == "Sewa kos")
    }

    @Test func aPurposeStopsAtFortyCharacters() {
        #expect(SharePurpose.cleaned(String(repeating: "a", count: 70)).count == 40)
        // A character as the user sees it, so an emoji is never cut in half.
        let emoji = String(repeating: "🏠", count: 41)
        #expect(SharePurpose.cleaned(emoji) == String(repeating: "🏠", count: 40))
        // What the field keeps while typing: the first forty characters as typed.
        #expect(SharePurpose.limited(String(repeating: "b", count: 45)) == String(repeating: "b", count: 40))
        #expect(SharePurpose.limited("Sewa kos") == "Sewa kos")
        // The cut comes after collapsing, so spaces typed in a row don't use up the length.
        #expect(SharePurpose.cleaned("a" + String(repeating: " ", count: 80) + "b") == "a b")
    }

    @Test func theMarkHasThePurposeAndTodayInIndonesian() throws {
        let date = try #require(ISO8601DateFormatter().date(from: "2026-11-04T09:00:00Z"))
        let utc = try #require(TimeZone(identifier: "UTC"))
        #expect(
            SharePurpose.mark(purpose: "  Sewa kos\nJl. Perintis ", date: date, timeZone: utc)
                == "Sewa kos Jl. Perintis · 4 Nov 2026")
        // As typed: capitals would run wider and change what the user wrote.
        #expect(SharePurpose.mark(purpose: "bank bca", date: date, timeZone: utc) == "bank bca · 4 Nov 2026")
    }
}
