//
//  ScanPages.swift
//  Parsers
//
//  Created by Inez Amanda on 26/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import VaultCore

/// How the pages of one scan relate, when people scan more than one card at once. Each page is parsed on
/// its own; this picks the page the fields come from and says what every other front is next to it.
public enum ScanPages {
    /// `pages` holds each page's parse, nil where no parser knew the text.
    public static func read(_ pages: [ParsedDocument?]) -> ScanReading {
        let fronts = pages.indices.filter { pages[$0].map(isFront) ?? false }
        guard let first = fronts.first, let firstPage = pages[first] else {
            return ScanReading(source: nil, pages: pages.map { _ in nil })
        }
        // Among the pages of the first front's card, the best read; on a tie, the first.
        let group = fronts.filter { pages[$0].map { isSameCard($0, firstPage) } ?? false }
        let source = group.min { marks(pages[$0]) < marks(pages[$1]) } ?? first
        guard let sourcePage = pages[source] else { return ScanReading(source: nil, pages: pages.map { _ in nil }) }
        let reads = pages.indices.map { index -> PageRead? in
            guard let page = pages[index], isFront(page) else { return nil }
            let relation = index == source ? .source : relation(of: page, to: sourcePage)
            return PageRead(
                type: page.type, relation: relation, reasons: page.reasons, typeReasons: page.typeReasons,
                expiryReasons: page.expiryReasons)
        }
        return ScanReading(source: source, pages: reads)
    }

    private static func relation(of page: ParsedDocument, to source: ParsedDocument) -> PageRelation {
        if isSameCard(page, source) { return page.type == .sim && source.type != .sim ? .classUnread : .sameCard }
        guard isSameKind(page, source) else { return .otherType }
        // Nothing on a card of mixed layouts can be trusted, its number's length included.
        if [page, source].contains(where: isMixedLayout) { return .unsureNumber }
        // An old SIM's 14 digits against a new one's 16 can't be a misread: an old card and its renewal.
        if page.type.isSIM, isWellFormed(page), isWellFormed(source),
            number(of: page)?.count != number(of: source)?.count
        {
            return .otherCard
        }
        return [page, source].contains(where: hasUnsureNumber) ? .unsureNumber : .otherCard
    }

    /// A KTP or SIM with its number read, well formed or not, as before pages were compared.
    private static func isFront(_ page: ParsedDocument) -> Bool {
        number(of: page) != nil
    }

    /// Exactly the same digits, both well formed, on the same type; a SIM read without its class counts
    /// with any SIM.
    private static func isSameCard(_ page: ParsedDocument, _ other: ParsedDocument) -> Bool {
        isSameKind(page, other) && isWellFormed(page) && isWellFormed(other) && number(of: page) == number(of: other)
    }

    private static func isSameKind(_ page: ParsedDocument, _ other: ParsedDocument) -> Bool {
        page.type == other.type || (page.type.isSIM && other.type.isSIM && (page.type == .sim || other.type == .sim))
    }

    private static func number(of page: ParsedDocument) -> String? {
        page.fields.values[FieldKey.nik] ?? page.fields.values[FieldKey.simNumber]
    }

    /// As read, nothing between the digits: a NIK with dashes is refused by the review, and the SIM parser
    /// stores its number as digits alone.
    private static func isWellFormed(_ page: ParsedDocument) -> Bool {
        guard let number = number(of: page) else { return false }
        return page.type.isSIM ? SIMParser.isWellFormedNumber(number) : NIK.isWellFormed(number)
    }

    /// A number the review would refuse, or one the parser marked, may be misread.
    private static func hasUnsureNumber(_ page: ParsedDocument) -> Bool {
        !isWellFormed(page)
            || !(page.reasons[FieldKey.nik, default: []].isEmpty
                && page.reasons[FieldKey.simNumber, default: []].isEmpty)
    }

    private static func isMixedLayout(_ page: ParsedDocument) -> Bool {
        page.typeReasons.contains(.mixedLayout) || page.reasons.values.contains { $0.contains(.mixedLayout) }
    }

    /// How many values are marked: the fields, the type and the expiry.
    private static func marks(_ page: ParsedDocument?) -> Int {
        guard let page else { return .max }
        return page.reasons.values.filter { !$0.isEmpty }.count + (page.typeReasons.isEmpty ? 0 : 1)
            + (page.expiryReasons.isEmpty ? 0 : 1)
    }
}

public struct ScanReading: Sendable, Equatable {
    /// The page the fields come from; nil when no page was read as a front.
    public var source: Int?
    /// One entry per page, nil for a page that isn't a front: a back, or one no parser knew.
    public var pages: [PageRead?]

    public init(source: Int?, pages: [PageRead?]) {
        self.source = source
        self.pages = pages
    }
}

/// What a front was read as, without any of its values: a page can be another person's card.
public struct PageRead: Sendable, Equatable {
    public var type: DocumentType
    public var relation: PageRelation
    public var reasons: [String: Set<CheckReason>]
    public var typeReasons: Set<CheckReason>
    public var expiryReasons: Set<CheckReason>

    public init(
        type: DocumentType, relation: PageRelation, reasons: [String: Set<CheckReason>] = [:],
        typeReasons: Set<CheckReason> = [], expiryReasons: Set<CheckReason> = []
    ) {
        self.type = type
        self.relation = relation
        self.reasons = reasons
        self.typeReasons = typeReasons
        self.expiryReasons = expiryReasons
    }
}

/// A front next to the source page.
public enum PageRelation: Sendable, Equatable {
    case source
    /// The same card scanned again: the same type and exactly the same digits.
    case sameCard
    /// The source's SIM again, read without its class.
    case classUnread
    /// The same type with other digits, but one of the numbers may be misread.
    case unsureNumber
    /// The same type with another number read cleanly: another card.
    case otherCard
    case otherType
}
