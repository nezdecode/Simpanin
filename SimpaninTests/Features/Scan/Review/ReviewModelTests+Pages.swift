//
//  ReviewModelTests+Pages.swift
//  SimpaninTests
//
//  Created by Inez Amanda on 26/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Parsers
import Testing
import VaultCore

@testable import Simpanin

/// The page notes come from the scan's reading and the type chosen now.
extension ReviewModelTests {
    static let ktpAndSIMReading = ScanReading(
        source: 0, pages: [PageRead(type: .ktp, relation: .source), PageRead(type: .simA, relation: .otherType)])

    func loadKTPAndSIM(into review: ReviewModel) throws {
        review.loadScan(Self.ktp, pages: [try page(), try page()], reading: Self.ktpAndSIMReading)
    }

    @Test func theNotesFollowTheReadingAndTheChosenType() throws {
        let review = model()
        try loadKTPAndSIM(into: review)
        #expect(review.pageNotes.notes == [nil, .otherType(.simA)])
        review.type = .passport
        #expect(review.pageNotes.notes == [.readAs(.ktp), .readAs(.simA)])
    }

    /// A rescan that fails comes without a reading, so nothing of the old scan is said about the new pages.
    @Test func aFailedRescanHasNoPageNotes() throws {
        let review = model()
        try loadKTPAndSIM(into: review)
        review.loadScan(nil, pages: [try page(), try page()], reading: nil)
        #expect(review.pageNotes.notes == [nil, nil])
        #expect(review.pageNotes.sentences.isEmpty)
    }

    @Test func aRescanReplacesEveryNote() throws {
        let review = model()
        try loadKTPAndSIM(into: review)
        let again = ScanReading(source: 1, pages: [nil, PageRead(type: .ktp, relation: .source)])
        review.loadScan(Self.ktp, pages: [try page(), try page()], reading: again)
        #expect(review.pageNotes.notes == [nil, nil])
        #expect(review.pageNotes.sentences == ["Isian dibaca dari halaman 2."])
    }

    /// The strip shows the thumbnails it was given, one per page, never the scan itself.
    @Test func loadKeepsAThumbnailPerPage() throws {
        let review = model()
        let pages = [try page(width: 8), try page(width: 8)]
        let thumbnails = [try page(), try page()]
        review.load(Self.ktp, pages: pages, thumbnails: thumbnails)
        #expect(review.thumbnails.count == 2)
        #expect(zip(review.thumbnails, thumbnails).allSatisfy { $0 === $1 })
        #expect(zip(review.pages, pages).allSatisfy { $0 === $1 })
    }

    @Test func aRescanReplacesTheThumbnails() throws {
        let review = model()
        review.load(Self.ktp, pages: [try page(), try page()], thumbnails: [try page(), try page()])
        let again = try page()
        review.load(Self.ktp, pages: [try page(width: 8)], thumbnails: [again])
        #expect(review.thumbnails.count == 1)
        #expect(review.thumbnails.first.flatMap { $0 } === again)
    }

    /// A thumbnail that can't be made leaves a placeholder; the scan's pages are kept and saved in full.
    @Test func aFailedThumbnailIsAPlaceholderAndThePagesStay() async throws {
        let review = model()
        let pages = [try page(), try page()]
        let thumbnails = await PageStrip.thumbnails(of: pages, reduce: { _, _ in nil })
        #expect(thumbnails.count == 2)
        #expect(thumbnails.allSatisfy { $0 == nil })
        review.load(Self.ktp, pages: pages, thumbnails: thumbnails)
        #expect(zip(review.pages, pages).allSatisfy { $0 === $1 })
    }
}
