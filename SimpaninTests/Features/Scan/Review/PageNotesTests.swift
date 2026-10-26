//
//  PageNotesTests.swift
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

@Suite("Page notes")
struct PageNotesTests {
    /// A reading from the pages' types and relations; nil is a back or an unread page.
    static func reading(_ pages: [(DocumentType, PageRelation)?]) -> ScanReading {
        ScanReading(
            source: pages.firstIndex { $0?.1 == .source },
            pages: pages.map { $0.map { PageRead(type: $0.0, relation: $0.1) } })
    }

    static func notes(_ pages: [(DocumentType, PageRelation)?], chosen: DocumentType = .ktp) -> PageNotes {
        PageNotes(reading: reading(pages), pageCount: pages.count, chosen: chosen)
    }

    static let ktpAndSIM: [(DocumentType, PageRelation)?] = [(.ktp, .source), (.simA, .otherType)]

    // MARK: Which page says what

    /// The fields came from the KTP page, whatever type is chosen now.
    @Test func notesFollowTheSourcePageNotTheChosenType() {
        let notes = Self.notes(Self.ktpAndSIM, chosen: .simA)
        #expect(notes.notes == [nil, .otherType(.simA)])
        #expect(notes.sentences.last == "Halaman 2 terbaca sebagai SIM A, bukan KTP di halaman 1.")
    }

    @Test func switchingTheTypeAwayAndBackRestoresTheNotes() {
        let before = Self.notes(Self.ktpAndSIM, chosen: .ktp)
        #expect(Self.notes(Self.ktpAndSIM, chosen: .passport).notes == [.readAs(.ktp), .readAs(.simA)])
        #expect(Self.notes(Self.ktpAndSIM, chosen: .ktp) == before)
    }

    @Test func aTypeWithoutAParserGetsReadAsOnEveryKTPOrSIMPage() {
        let notes = Self.notes([(.ktp, .source), nil, (.simA, .otherType)], chosen: .passport)
        #expect(notes.notes == [.readAs(.ktp), nil, .readAs(.simA)])
    }

    /// Useful when the wrong type was picked, or a KTP was scanned with an STNK.
    @Test func aSinglePageWithATypeWithoutAParserIsReadAs() {
        let notes = Self.notes([(.ktp, .source)], chosen: .stnk)
        #expect(notes.notes == [.readAs(.ktp)])
        #expect(notes.sentences == ["Halaman 1 terbaca sebagai KTP."])
    }

    @Test func aSinglePageOfItsOwnTypeHasNoNotes() {
        let notes = Self.notes([(.ktp, .source)])
        #expect(notes.notes == [nil])
        #expect(notes.sentences.isEmpty)
    }

    /// Such a type has no fields, so there's nothing for the line to say.
    @Test func aTypeWithoutAParserHasNoSourceLine() {
        #expect(!Self.notes([nil, (.ktp, .source)], chosen: .other).showsSource)
    }

    @Test func theSourceLineShowsWhenTheSourceIsntPage1() {
        #expect(Self.notes([nil, (.ktp, .source)]).sentences == ["Isian dibaca dari halaman 2."])
    }

    /// The fields on screen are a SIM's, but they were read from a KTP.
    @Test func theSourceLineShowsWhenKTPAndSIMAreSwapped() {
        #expect(Self.notes([(.ktp, .source)], chosen: .simA).sentences == ["Isian dibaca dari halaman 1."])
    }

    /// A class picked by hand is a correction, not another document.
    @Test func anotherSIMClassChosenShowsNoSourceLine() {
        #expect(!Self.notes([(.simA, .source)], chosen: .simC).showsSource)
    }

    @Test func theNoFrontFallbackHasNoSourceLine() {
        let notes = Self.notes([nil, nil])
        #expect(notes.notes == [nil, nil])
        #expect(notes.sentences.isEmpty)
    }

    @Test func neutralNotesAreNotMarked() {
        #expect(PageNotes.Note.otherType(.ktp).isMarked)
        #expect(PageNotes.Note.otherCard(.ktp).isMarked)
        #expect(PageNotes.Note.readAs(.ktp).isMarked)
        #expect(!PageNotes.Note.classUnread.isMarked)
        #expect(!PageNotes.Note.unsureNumber(.ktp).isMarked)
    }

    /// Notes can never point at a page that isn't shown.
    @Test func aReadingOfAnotherPageCountIsIgnored() {
        let notes = PageNotes(reading: Self.reading(Self.ktpAndSIM), pageCount: 3, chosen: .ktp)
        #expect(notes.notes == [nil, nil, nil])
        #expect(notes.sentences.isEmpty)
    }

    // MARK: The sentences

    @Test func oneOtherPageSentence() {
        #expect(Self.notes(Self.ktpAndSIM).sentences == ["Halaman 2 terbaca sebagai SIM A, bukan KTP di halaman 1."])
    }

    @Test func twoAndThreePagesAreJoined() {
        let two = Self.notes([(.ktp, .source), (.simA, .otherType), (.simA, .otherType)])
        #expect(two.sentences == ["Halaman 2 dan 3 terbaca sebagai SIM A, bukan KTP di halaman 1."])
        let three = Self.notes([(.ktp, .source), (.simA, .otherType), (.simA, .otherType), (.simA, .otherType)])
        #expect(three.sentences == ["Halaman 2, 3, dan 4 terbaca sebagai SIM A, bukan KTP di halaman 1."])
    }

    @Test func twoKindsGiveTwoSentences() {
        let notes = Self.notes([(.ktp, .source), (.simA, .otherType), (.ktp, .otherCard)])
        #expect(
            notes.sentences == [
                "Halaman 2 terbaca sebagai SIM A, bukan KTP di halaman 1.", "Halaman 3 terbaca sebagai KTP lain.",
            ])
    }

    @Test func moreThanTwoBadgeSentencesBecomeOne() {
        let notes = Self.notes([(.ktp, .source), (.simA, .otherType), (.simC, .otherType), (.ktp, .otherCard)])
        #expect(notes.sentences == ["Beberapa halaman terbaca sebagai dokumen lain."])
    }

    @Test func readAsOfOneKindIsListedNotCollapsed() {
        let notes = Self.notes([(.ktp, .source), (.ktp, .sameCard), (.ktp, .otherCard)], chosen: .passport)
        #expect(notes.sentences == ["Halaman 1, 2, dan 3 terbaca sebagai KTP."])
    }

    /// With no source page, the chosen type is what the other documents aren't.
    @Test func readAsOfThreeKindsCollapsesAgainstTheChosenType() {
        let pages: [(DocumentType, PageRelation)?] = [(.ktp, .source), (.simA, .otherType), (.simC, .otherType)]
        #expect(
            Self.notes(pages, chosen: .passport).sentences == [
                "Beberapa halaman terbaca sebagai dokumen lain, bukan paspor."
            ])
        #expect(
            Self.notes(pages, chosen: .other).sentences == [
                "Beberapa halaman terbaca sebagai dokumen lain, bukan dokumen Lainnya."
            ])
    }

    /// Its key is built at run time, so a type added to the picker without its text would show the key.
    @Test func everyTypeWithoutAParserHasItsCollapseText() {
        let pages: [(DocumentType, PageRelation)?] = [(.ktp, .source), (.simA, .otherType), (.simC, .otherType)]
        for type in TypePickerView.types where ReviewModel.fieldKeys(for: type).isEmpty {
            let sentence = Self.notes(pages, chosen: type).sentences.first ?? ""
            #expect(sentence.hasPrefix("Beberapa halaman terbaca sebagai dokumen lain, bukan "), "\(type.rawValue)")
        }
    }

    @Test func neutralNotesStayAfterTheCollapse() {
        let notes = Self.notes([
            (.ktp, .source), (.simA, .otherType), (.simC, .otherType), (.ktp, .otherCard), (.ktp, .unsureNumber),
        ])
        #expect(
            notes.sentences == [
                "Beberapa halaman terbaca sebagai dokumen lain.",
                "Halaman 5 juga KTP, tapi nomornya belum bisa dipastikan sama.",
            ])
    }

    @Test func aSIMWithoutAClassIsNamedSIM() {
        #expect(
            Self.notes([(.simA, .source), (.sim, .classUnread)], chosen: .simA).sentences == [
                "Halaman 2 juga SIM, tapi golongannya tidak terbaca."
            ])
        #expect(
            Self.notes([(.ktp, .source), (.sim, .otherType)]).sentences == [
                "Halaman 2 terbaca sebagai SIM, bukan KTP di halaman 1."
            ])
    }

    /// Lines about a page with a badge are shown like a mark; the source line and neutral notes aren't.
    @Test func linesAboutBadgedPagesAreMarked() {
        let notes = Self.notes([nil, (.ktp, .source), (.simA, .otherType), (.ktp, .unsureNumber)])
        #expect(notes.lines.map(\.isMarked) == [false, true, false])
    }

    @Test func theFooterOrder() {
        let notes = Self.notes([nil, (.ktp, .source), (.simA, .otherType)])
        #expect(
            notes.sentences == [
                "Isian dibaca dari halaman 2.", "Halaman 3 terbaca sebagai SIM A, bukan KTP di halaman 2.",
            ])
    }

    @Test func pageAccessibilityLabels() {
        let notes = Self.notes([
            (.ktp, .source), (.simA, .otherType), (.ktp, .otherCard), (.ktp, .unsureNumber), nil,
        ])
        #expect(notes.accessibilityLabel(page: 0) == "Halaman 1 dari 5, isian dibaca dari halaman ini")
        #expect(notes.accessibilityLabel(page: 1) == "Halaman 2 dari 5, terbaca sebagai SIM A")
        #expect(notes.accessibilityLabel(page: 2) == "Halaman 3 dari 5, terbaca sebagai KTP lain")
        #expect(notes.accessibilityLabel(page: 3) == "Halaman 4 dari 5, juga KTP, nomor belum pasti sama")
        #expect(notes.accessibilityLabel(page: 4) == "Halaman 5 dari 5")
        let classless = Self.notes([(.simA, .source), (.sim, .classUnread)], chosen: .simA)
        #expect(classless.accessibilityLabel(page: 1) == "Halaman 2 dari 2, juga SIM, golongan tidak terbaca")
        // No fields with a type without a parser, so the source page reads what it was read as.
        let readAs = Self.notes([(.ktp, .source)], chosen: .passport)
        #expect(readAs.accessibilityLabel(page: 0) == "Halaman 1 dari 1, terbaca sebagai KTP")
        // A single page of its own type says nothing more.
        #expect(Self.notes([(.ktp, .source)]).accessibilityLabel(page: 0) == "Halaman 1 dari 1")
    }
}
