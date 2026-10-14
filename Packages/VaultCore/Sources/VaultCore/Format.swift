//
//  Format.swift
//  VaultCore
//
//  Created by Inez Amanda on 4/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

// Everything VaultCore writes to disk. Once a format ships it never changes: a change here
// needs a new version, a migration and a fixture test.

// MARK: - vault.json

public struct KeySlotKind: RawRepresentable, Hashable, Sendable, Codable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    /// The MVP slot. The vault key is the Keychain item itself, so nothing is sealed here.
    public static let device = KeySlotKind(rawValue: "device")
}

/// A way to unlock the vault key. Only "device" exists in v1.
public struct KeySlot: Hashable, Sendable, Codable {
    public var kind: KeySlotKind
    public var createdAt: Date
    public var sealedVaultKey: Data?

    public init(kind: KeySlotKind, createdAt: Date, sealedVaultKey: Data? = nil) {
        self.kind = kind
        self.createdAt = createdAt
        self.sealedVaultKey = sealedVaultKey
    }
}

/// vault.json. It's plaintext and holds no secret.
public struct VaultHeader: Hashable, Sendable, Codable {
    public static let currentFormatVersion = 1

    public var formatVersion: Int
    public var vaultID: VaultID
    public var keySlots: [KeySlot]

    // The JSON keys are part of the v1 format, so they keep their original spelling.
    enum CodingKeys: String, CodingKey {
        case formatVersion, keySlots
        case vaultID = "vaultId"
    }

    public init(vaultID: VaultID, keySlots: [KeySlot]) {
        formatVersion = Self.currentFormatVersion
        self.vaultID = vaultID
        self.keySlots = keySlots
    }
}

// MARK: - index.enc

struct IndexEntry: Hashable, Sendable, Codable {
    var id: DocumentID
    var type: DocumentType
    /// Added in index schema version 2. Missing in version 1, where it reads as nil.
    var label: String?
    var createdAt: Date
    var updatedAt: Date
    var expiry: CalendarDate?
    var pinned: Bool
    var deletedAt: Date?
    /// The document key sealed with the wrap key and "dk|v1|<docId>".
    var sealedKey: Data
    /// DocumentFields JSON sealed with the document key and "fields|v1|<docId>".
    var sealedFields: Data
    var pageIDs: [PageID]

    enum CodingKeys: String, CodingKey {
        case id, type, label, createdAt, updatedAt, expiry, pinned, deletedAt, sealedKey, sealedFields
        case pageIDs = "pageIds"
    }

    var document: Document {
        Document(
            id: id, type: type, label: label, createdAt: createdAt, updatedAt: updatedAt, expiry: expiry,
            pinned: pinned, deletedAt: deletedAt, pageIDs: pageIDs)
    }
}

/// The plaintext of index.enc, sealed with the index key and "index|v1|<vaultId>".
struct VaultIndex: Hashable, Sendable, Codable {
    /// 2 added the optional document label.
    static let currentSchemaVersion = 2

    var schemaVersion: Int
    var generation: UInt64
    var documents: [IndexEntry]

    init(generation: UInt64, documents: [IndexEntry]) {
        schemaVersion = Self.currentSchemaVersion
        self.generation = generation
        self.documents = documents
    }
}

// MARK: - pages/<pageId>.enc

/// The plaintext header of a page file. It carries the sealed document key so pages
/// can be recovered when both index files are unreadable.
struct PageHeader: Hashable, Sendable, Codable {
    static let currentFormatVersion = 1

    var formatVersion: Int
    var documentID: DocumentID
    var pageID: PageID
    /// The page's index in its document, so recovery restores the page order.
    var position: Int
    var sealedKey: Data

    enum CodingKeys: String, CodingKey {
        case formatVersion, position, sealedKey
        case documentID = "docId"
        case pageID = "pageId"
    }

    init(documentID: DocumentID, pageID: PageID, position: Int, sealedKey: Data) {
        formatVersion = Self.currentFormatVersion
        self.documentID = documentID
        self.pageID = pageID
        self.position = position
        self.sealedKey = sealedKey
    }
}

/// A page file is a 4-byte big-endian header length, the header JSON, then the content
/// sealed with the document key and "page|v1|<docId>|<pageId>".
struct PageFile {
    static let maxHeaderLength = 64 * 1024

    var header: PageHeader
    var sealedContent: Data

    init(header: PageHeader, sealedContent: Data) {
        self.header = header
        self.sealedContent = sealedContent
    }

    init(decoding data: Data) throws {
        // Index from startIndex: a slice of a larger Data doesn't start at 0.
        let start = data.startIndex
        guard data.count >= 4 else { throw VaultError.corruptFile }
        let length = data[start..<start + 4].reduce(0) { $0 << 8 | Int($1) }
        guard length > 0, length <= Self.maxHeaderLength, data.count >= 4 + length else {
            throw VaultError.corruptFile
        }
        let headerEnd = start + 4 + length
        do {
            header = try VaultJSON.decoder.decode(PageHeader.self, from: data[(start + 4)..<headerEnd])
        } catch {
            throw VaultError.corruptFile
        }
        sealedContent = Data(data[headerEnd...])
    }

    func encoded() throws -> Data {
        let headerData = try VaultJSON.encoder.encode(header)
        let length = UInt32(headerData.count)
        var out = Data([
            UInt8(length >> 24 & 0xFF), UInt8(length >> 16 & 0xFF),
            UInt8(length >> 8 & 0xFF), UInt8(length & 0xFF),
        ])
        out += headerData
        out += sealedContent
        return out
    }
}

// MARK: - projection.json

/// What reminders and widgets can see without Face ID. No title, number, name or page.
public struct ProjectionEntry: Hashable, Sendable, Codable {
    public var id: DocumentID
    public var type: DocumentType
    public var expiry: CalendarDate?
    public var reminderOffsets: [Int]

    public init(id: DocumentID, type: DocumentType, expiry: CalendarDate?, reminderOffsets: [Int]) {
        self.id = id
        self.type = type
        self.expiry = expiry
        self.reminderOffsets = reminderOffsets
    }
}

/// projection.json, in plaintext, with one entry per live document.
public struct Projection: Hashable, Sendable, Codable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var documents: [ProjectionEntry]

    public init(documents: [ProjectionEntry]) {
        schemaVersion = Self.currentSchemaVersion
        self.documents = documents
    }
}

// MARK: - JSON settings shared by every file

enum VaultJSON {
    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        encoder.dataEncodingStrategy = .base64
        return encoder
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.dataDecodingStrategy = .base64
        return decoder
    }
}
