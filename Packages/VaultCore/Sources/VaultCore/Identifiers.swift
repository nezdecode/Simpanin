//
//  Identifiers.swift
//  VaultCore
//
//  Created by Inez Amanda on 4/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

/// A UUID-based identifier. Its text form is the lowercase UUID string, and that same text
/// goes into JSON, associated data, file names and the HKDF salt.
public struct Identifier<Kind>: Hashable, Sendable {
    public let uuid: UUID

    public init() { uuid = UUID() }
    public init(_ uuid: UUID) { self.uuid = uuid }

    /// Accepts only the canonical lowercase form, so one id has exactly one spelling.
    public init?(string: String) {
        guard let uuid = UUID(uuidString: string), uuid.uuidString.lowercased() == string else { return nil }
        self.uuid = uuid
    }

    public var string: String { uuid.uuidString.lowercased() }
}

extension Identifier: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let id = Identifier(string: text) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not a lowercase UUID")
        }
        self = id
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(string)
    }
}

public enum VaultIDKind {}
public enum DocumentIDKind {}
public enum PageIDKind {}

public typealias VaultID = Identifier<VaultIDKind>
public typealias DocumentID = Identifier<DocumentIDKind>
public typealias PageID = Identifier<PageIDKind>
