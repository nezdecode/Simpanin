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
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2])
        else { return nil }
        self.init(year: y, month: m, day: d)
    }

    public var string: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public static func < (a: CalendarDate, b: CalendarDate) -> Bool {
        (a.year, a.month, a.day) < (b.year, b.month, b.day)
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

/// The reviewed fields of a document (number, name, issue date, title...). Sealed with
/// the document key; never in the projection, never logged.
public struct DocumentFields: Hashable, Sendable, Codable {
    public var values: [String: String]
    public init(_ values: [String: String] = [:]) { self.values = values }
}

/// A document's metadata as the app sees it. Holds no secrets.
public struct Document: Hashable, Sendable, Identifiable {
    public let id: DocumentID
    public var type: DocumentType
    public var createdAt: Date
    public var updatedAt: Date
    public var expiry: CalendarDate?
    public var pinned: Bool
    /// Set while the document is in Recently deleted.
    public var deletedAt: Date?
    /// Page ids in display order.
    public var pageIDs: [PageID]
}

/// One decrypted page: image or PDF bytes, exactly as given to the vault. The app
/// detects the format from the bytes.
public struct Page: Hashable, Sendable, Identifiable {
    public let id: PageID
    public let data: Data
}

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

    /// The MVP slot: the vault key is the Keychain item itself, so nothing is sealed here.
    public static let device = KeySlotKind(rawValue: "device")
}

/// A way to unlock the vault key. v1.1 adds "synced" and "recovery" slots, each holding
/// the vault key sealed under another key.
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

/// vault.json: plaintext, holds no secret.
public struct VaultHeader: Hashable, Sendable, Codable {
    public static let currentFormatVersion = 1

    public var formatVersion: Int
    public var vaultId: VaultID
    public var keySlots: [KeySlot]

    public init(vaultId: VaultID, keySlots: [KeySlot]) {
        formatVersion = Self.currentFormatVersion
        self.vaultId = vaultId
        self.keySlots = keySlots
    }
}

// MARK: - index.enc

struct IndexEntry: Hashable, Sendable, Codable {
    var id: DocumentID
    var type: DocumentType
    var createdAt: Date
    var updatedAt: Date
    var expiry: CalendarDate?
    var pinned: Bool
    var deletedAt: Date?
    /// The document key sealed with the wrap key and "dk|v1|<docId>".
    var sealedKey: Data
    /// DocumentFields JSON sealed with the document key and "fields|v1|<docId>".
    var sealedFields: Data
    var pageIds: [PageID]

    var document: Document {
        Document(id: id, type: type, createdAt: createdAt, updatedAt: updatedAt, expiry: expiry,
                 pinned: pinned, deletedAt: deletedAt, pageIDs: pageIds)
    }
}

/// The plaintext of index.enc, sealed with the index key and "index|v1|<vaultId>".
struct VaultIndex: Hashable, Sendable, Codable {
    static let currentSchemaVersion = 1

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
    var docId: DocumentID
    var pageId: PageID
    var sealedKey: Data

    init(docId: DocumentID, pageId: PageID, sealedKey: Data) {
        formatVersion = Self.currentFormatVersion
        self.docId = docId
        self.pageId = pageId
        self.sealedKey = sealedKey
    }
}

/// Layout: 4-byte big-endian header length, header JSON, then the content sealed with
/// the document key and "page|v1|<docId>|<pageId>".
struct PageFile {
    static let maxHeaderLength = 64 * 1024

    var header: PageHeader
    var sealedContent: Data

    init(header: PageHeader, sealedContent: Data) {
        self.header = header
        self.sealedContent = sealedContent
    }

    init(decoding data: Data) throws {
        let bytes = [UInt8](data)
        guard bytes.count >= 4 else { throw VaultError.corruptFile }
        let length = bytes[0..<4].reduce(0) { $0 << 8 | Int($1) }
        guard length > 0, length <= Self.maxHeaderLength, bytes.count >= 4 + length else {
            throw VaultError.corruptFile
        }
        do {
            header = try VaultJSON.decoder.decode(PageHeader.self, from: Data(bytes[4..<(4 + length)]))
        } catch {
            throw VaultError.corruptFile
        }
        sealedContent = Data(bytes[(4 + length)...])
    }

    func encoded() throws -> Data {
        let headerData = try VaultJSON.encoder.encode(header)
        let length = UInt32(headerData.count)
        var out = Data([UInt8(length >> 24 & 0xFF), UInt8(length >> 16 & 0xFF),
                        UInt8(length >> 8 & 0xFF), UInt8(length & 0xFF)])
        out += headerData
        out += sealedContent
        return out
    }
}

// MARK: - projection.json

/// What reminders and widgets may see without Face ID: no title, number, name or page.
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

/// projection.json: plaintext, one entry per live (not deleted) document.
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
