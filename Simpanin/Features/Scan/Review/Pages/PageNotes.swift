//
//  PageNotes.swift
//  Simpanin
//
//  Created by Inez Amanda on 26/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import Parsers
import VaultCore

/// What Periksa data says about the pages of one scan: which page the fields came from, and what each
/// other card was read as. Worked out each time from the reading and the chosen type, never stored, so a
/// type changed and changed back says the same again.
nonisolated struct PageNotes: Equatable {
    enum Note: Equatable {
        /// Another kind of document than the source page's.
        case otherType(DocumentType)
        /// The same type with another number read cleanly.
        case otherCard(DocumentType)
        /// A type without a parser was chosen; this page read as a KTP or SIM.
        case readAs(DocumentType)
        /// The source's SIM again, without its class.
        case classUnread
        /// The same type with other digits, one of them possibly misread.
        case unsureNumber(DocumentType)

        /// Neutral notes claim nothing, so their thumbnail has no badge.
        var isMarked: Bool {
            switch self {
            case .otherType, .otherCard, .readAs: true
            case .classUnread, .unsureNumber: false
            }
        }
    }

    /// One per page, nil where there's nothing to say.
    let notes: [Note?]
    /// The page the fields came from, counted from 0; nil without one.
    let source: Int?
    /// "Isian dibaca dari halaman N." shows.
    let showsSource: Bool
    let sourceType: DocumentType?
    let chosen: DocumentType

    /// A reading for another number of pages than shown is ignored: it belongs to another scan.
    init(reading: ScanReading?, pageCount: Int, chosen: DocumentType) {
        self.chosen = chosen
        guard let reading, reading.pages.count == pageCount, let source = reading.source,
            reading.pages.indices.contains(source), let sourceType = reading.pages[source]?.type
        else {
            (notes, self.source, showsSource, self.sourceType) = (
                Array(repeating: nil, count: pageCount), nil, false, nil
            )
            return
        }
        self.source = source
        self.sourceType = sourceType
        let fields = DocumentFieldStyle.keys(for: chosen)
        // A type without a parser has no fields and no source to compare with, so each card says what it is.
        guard !fields.isEmpty else {
            notes = reading.pages.map { $0.map { .readAs($0.type) } }
            showsSource = false
            return
        }
        notes = reading.pages.map { $0.flatMap(Self.note) }
        // A class picked by hand keeps the same fields, so it's a correction, not another document.
        showsSource = source != 0 || fields != DocumentFieldStyle.keys(for: sourceType)
    }

    private static func note(for page: PageRead) -> Note? {
        switch page.relation {
        case .source, .sameCard: nil
        case .classUnread: .classUnread
        case .unsureNumber: .unsureNumber(page.type)
        case .otherCard: .otherCard(page.type)
        case .otherType: .otherType(page.type)
        }
    }

    /// A line of the footer; a marked one is about a page with a badge, and is shown like it.
    struct Line: Equatable {
        let text: String
        let isMarked: Bool
    }

    /// The footer's lines after "N halaman", in order: the source line, the badged notes (more than two of
    /// them become one), then the neutral ones.
    var lines: [Line] {
        var lines: [Line] = []
        if showsSource, let source {
            lines.append(Line(text: String(localized: "pageNotes.source \(source + 1)"), isMarked: false))
        }
        let groups = groups
        let marked = groups.filter(\.note.isMarked)
        if marked.count > 2 {
            lines.append(Line(text: several, isMarked: true))
        } else {
            lines += marked.map { Line(text: sentence($0), isMarked: true) }
        }
        lines += groups.filter { !$0.note.isMarked }.map { Line(text: sentence($0), isMarked: false) }
        return lines
    }

    var sentences: [String] { lines.map(\.text) }

    /// What Simpan asks when a page has a badge: what those pages were read as, and that every page is
    /// saved as one document of the chosen type. Nil without a badge.
    var saveWarning: String? {
        let marked = groups.filter(\.note.isMarked)
        guard !marked.isEmpty else { return nil }
        var sentences: [String]
        if marked.count > 2 {
            sentences = [String(localized: "pageNotes.several")]
        } else if showsSource {
            sentences = marked.map(sentence)
        } else {
            // Without the source line, the last sentence names the chosen type, so another type says only
            // what it was read as.
            sentences = marked.map { group in
                guard case .otherType(let type) = group.note else { return sentence(group) }
                return sentence((.readAs(type), group.pages))
            }
        }
        // As in the footer: fields read from a KTP and saved as a SIM A would otherwise go unsaid.
        if showsSource, let source { sentences.append(String(localized: "pageNotes.source \(source + 1)")) }
        return (sentences + [savedAs]).joined(separator: " ")
    }

    /// "Semua halaman akan disimpan sebagai satu dokumen KTP." A type without a parser has its own words,
    /// like "paspor"; its key is built as a plain string, as in `several`.
    private var savedAs: String {
        guard DocumentFieldStyle.keys(for: chosen).isEmpty else {
            return String(localized: "pageNotes.savedAs \(Self.name(chosen))")
        }
        return String(localized: String.LocalizationValue("pageNotes.savedAs." + chosen.rawValue))
    }

    /// What VoiceOver reads for a page, counted from 0.
    func accessibilityLabel(page: Int) -> String {
        guard let detail = detail(page) else { return String(localized: "review.pageOf \(page + 1) \(notes.count)") }
        return String(localized: "pageNotes.labelWith \(page + 1) \(notes.count) \(detail)")
    }

    /// Pages with the same note, in the order they first appear; page numbers count from 1.
    private var groups: [(note: Note, pages: [Int])] {
        var groups: [(note: Note, pages: [Int])] = []
        for (index, note) in notes.enumerated() {
            guard let note else { continue }
            if let group = groups.firstIndex(where: { $0.note == note }) {
                groups[group].pages.append(index + 1)
            } else {
                groups.append((note, [index + 1]))
            }
        }
        return groups
    }

    private func sentence(_ group: (note: Note, pages: [Int])) -> String {
        let pages = String(localized: "pageNotes.pages \(Self.list(group.pages))")
        switch group.note {
        case .otherType(let type):
            let source = (source ?? 0) + 1
            return String(
                localized: "pageNotes.otherType \(pages) \(Self.name(type)) \(Self.name(sourceType)) \(source)")
        case .otherCard(let type): return String(localized: "pageNotes.otherCard \(pages) \(Self.name(type))")
        case .readAs(let type): return String(localized: "pageNotes.readAs \(pages) \(Self.name(type))")
        case .classUnread: return String(localized: "pageNotes.classUnread \(pages)")
        case .unsureNumber(let type): return String(localized: "pageNotes.unsureNumber \(pages) \(Self.name(type))")
        }
    }

    /// With no source to compare with, the chosen type is what the other documents aren't. The key is built
    /// as a plain string: interpolated, the type would become an argument.
    private var several: String {
        guard DocumentFieldStyle.keys(for: chosen).isEmpty else {
            return String(localized: "pageNotes.several")
        }
        return String(localized: String.LocalizationValue("pageNotes.severalNot." + chosen.rawValue))
    }

    private func detail(_ page: Int) -> String? {
        switch notes[page] {
        case .otherType(let type)?, .readAs(let type)?:
            return String(localized: "pageNotes.label.readAs \(Self.name(type))")
        case .otherCard(let type)?: return String(localized: "pageNotes.label.otherCard \(Self.name(type))")
        case .classUnread?: return String(localized: "pageNotes.label.classUnread")
        case .unsureNumber(let type)?: return String(localized: "pageNotes.label.unsureNumber \(Self.name(type))")
        case nil:
            // Said only where it helps: the source isn't page 1, or other pages have notes.
            guard page == source, showsSource || notes.contains(where: { $0 != nil }) else { return nil }
            return String(localized: "pageNotes.label.source")
        }
    }

    private static func name(_ type: DocumentType?) -> String {
        String(localized: DocumentStyle.name(type ?? .other))
    }

    /// "2", "2 dan 3", "2, 3, dan 4", always in Indonesian like every text in the app.
    private static func list(_ pages: [Int]) -> String {
        pages.map(String.init).formatted(.list(type: .and).locale(.indonesian))
    }
}
