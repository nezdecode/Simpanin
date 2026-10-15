//
//  Models.swift
//  VaultCore
//
//  Created by Inez Amanda on 4/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

// MARK: - Public models

/// The kind of document. An open set of strings, so a vault written by a newer build
/// with a new type still decodes.
public struct DocumentType: RawRepresentable, Hashable, Sendable, Codable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public static let ktp = DocumentType(rawValue: "ktp")
    public static let kk = DocumentType(rawValue: "kk")
    public static let sim = DocumentType(rawValue: "sim")
    public static let stnk = DocumentType(rawValue: "stnk")
    public static let passport = DocumentType(rawValue: "passport")
    public static let npwp = DocumentType(rawValue: "npwp")
    public static let bpjs = DocumentType(rawValue: "bpjs")
    public static let other = DocumentType(rawValue: "other")

    // SIM by class (Perpol 5/2021 Pasal 3 ayat (2)). One class is one document with its own expiry.
    // These ids are stored in every vault: never rename one. `sim` stays for vaults made before them.
    public static let simA = DocumentType(rawValue: "sim-a")
    public static let simB1 = DocumentType(rawValue: "sim-b1")
    public static let simB2 = DocumentType(rawValue: "sim-b2")
    public static let simC = DocumentType(rawValue: "sim-c")
    public static let simC1 = DocumentType(rawValue: "sim-c1")
    public static let simC2 = DocumentType(rawValue: "sim-c2")
    public static let simD = DocumentType(rawValue: "sim-d")
    public static let simD1 = DocumentType(rawValue: "sim-d1")
    public static let simAUmum = DocumentType(rawValue: "sim-a-umum")
    public static let simB1Umum = DocumentType(rawValue: "sim-b1-umum")
    public static let simB2Umum = DocumentType(rawValue: "sim-b2-umum")

    /// Every SIM class, private ones first, then the Umum ones.
    public static let simClasses: [DocumentType] = [
        .simA, .simB1, .simB2, .simC, .simC1, .simC2, .simD, .simD1, .simAUmum, .simB1Umum, .simB2Umum,
    ]

    /// A SIM of any class, or the classless `sim` of older vaults.
    public var isSIM: Bool { self == .sim || Self.simClasses.contains(self) }
}

/// A day on the calendar with no time or time zone, stored as "YYYY-MM-DD". Expiry
/// dates use this so a time-zone change never moves them.
public struct CalendarDate: Hashable, Sendable, Comparable {
    public let year: Int
    public let month: Int
    public let day: Int

    public init?(year: Int, month: Int, day: Int) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = DateComponents(year: year, month: month, day: day)
        guard (1...9999).contains(year), (1...12).contains(month),
            let date = calendar.date(from: components),
            calendar.dateComponents([.year, .month, .day], from: date) == components
        else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    public init?(_ text: String) {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
            text.allSatisfy({ $0 == "-" || ("0"..."9").contains($0) }),
            let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2])
        else { return nil }
        self.init(year: year, month: month, day: day)
    }

    public var string: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public static func < (lhs: CalendarDate, rhs: CalendarDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}

extension CalendarDate: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        guard let date = CalendarDate(try container.decode(String.self)) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected YYYY-MM-DD")
        }
        self = date
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(string)
    }
}

/// The keys of `DocumentFields`. They're stored in every document, so they never change, and each
/// is named for what the value means rather than the document it came from: `name` is the same key
/// on a KTP, a SIM and a passport.
public enum FieldKey {
    public static let nik = "nik"
    public static let name = "name"
    public static let birthDate = "birthDate"
    /// On a SIM made from July 2024 this is the holder's NIK; on older cards it isn't.
    public static let simNumber = "simNumber"
}

/// A document's fields, like number, name and dates. They never go in the projection and
/// are never logged.
public struct DocumentFields: Hashable, Sendable, Codable {
    public var values: [String: String]
    public init(_ values: [String: String] = [:]) { self.values = values }
}

/// A document's metadata as the app sees it. Holds no secrets.
public struct Document: Hashable, Sendable, Identifiable {
    public let id: DocumentID
    public var type: DocumentType
    /// A short name the user picks to tell documents apart, like "Ibu". Shown on the list, so
    /// it's kept in the index and never in the projection.
    public var label: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var expiry: CalendarDate?
    public var pinned: Bool
    /// Set while the document is in Recently deleted.
    public var deletedAt: Date?
    /// Page ids in display order.
    public var pageIDs: [PageID]
}

/// One decrypted page: the image or PDF bytes exactly as stored.
public struct Page: Hashable, Sendable, Identifiable {
    public let id: PageID
    public let data: Data
}
