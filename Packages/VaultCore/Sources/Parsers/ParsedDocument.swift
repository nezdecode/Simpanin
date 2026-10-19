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
    /// Why each field the parser isn't sure about is marked "Periksa lagi". Every reason is kept, so
    /// fixing one, like a birth date that now matches, never hides another.
    public var reasons: [String: Set<CheckReason>]
    /// The type and the expiry aren't fields, so their reasons are kept here.
    public var typeReasons: Set<CheckReason>
    public var expiryReasons: Set<CheckReason>
    /// The birth date inside the NIK, or a new SIM's number, matches the printed one, and nothing about
    /// either was corrected or marked. It checks 6 of the 16 digits, so it's never shown as a verification.
    public var birthDateConfirmed: Bool

    public var needsCheck: Set<String> { Set(reasons.filter { !$0.value.isEmpty }.keys) }
    public var typeNeedsCheck: Bool { !typeReasons.isEmpty }
    public var expiryNeedsCheck: Bool { !expiryReasons.isEmpty }

    public init(
        type: DocumentType, fields: DocumentFields, expiry: CalendarDate?, reasons: [String: Set<CheckReason>] = [:],
        typeReasons: Set<CheckReason> = [], expiryReasons: Set<CheckReason> = [], birthDateConfirmed: Bool = false
    ) {
        self.type = type
        self.fields = fields
        self.expiry = expiry
        self.reasons = reasons
        self.typeReasons = typeReasons
        self.expiryReasons = expiryReasons
        self.birthDateConfirmed = birthDateConfirmed
    }
}
