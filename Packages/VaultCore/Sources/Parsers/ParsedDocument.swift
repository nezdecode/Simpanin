//
//  ParsedDocument.swift
//  Parsers
//
//  Created by Inez Amanda on 15/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import VaultCore

/// What a parser read from a document, for the review screen. Nothing here is saved as it is: the
/// user checks and corrects it first.
public struct ParsedDocument: Sendable, Equatable {
    public var type: DocumentType
    public var fields: DocumentFields
    public var expiry: CalendarDate?
    /// Fields the parser isn't sure about, marked "Periksa lagi" on the review screen.
    public var needsCheck: Set<String>
    /// The type and the expiry aren't fields, so they're marked here.
    public var typeNeedsCheck: Bool
    public var expiryNeedsCheck: Bool

    public init(
        type: DocumentType, fields: DocumentFields, expiry: CalendarDate?, needsCheck: Set<String>,
        typeNeedsCheck: Bool = false, expiryNeedsCheck: Bool = false
    ) {
        self.type = type
        self.fields = fields
        self.expiry = expiry
        self.needsCheck = needsCheck
        self.typeNeedsCheck = typeNeedsCheck
        self.expiryNeedsCheck = expiryNeedsCheck
    }
}
