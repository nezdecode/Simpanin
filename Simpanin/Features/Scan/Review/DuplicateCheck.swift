//
//  DuplicateCheck.swift
//  Simpanin
//
//  Created by Inez Amanda on 27/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import OSLog
import VaultCore

/// Whether the vault already holds the KTP or SIM about to be saved. A warning only: it never blocks
/// a save, and the saved fields it reads are compared in memory and never kept.
nonisolated enum DuplicateCheck {
    /// The document about to be saved, as far as the check compares it.
    struct Candidate: Hashable, Sendable {
        let type: DocumentType
        /// Digits only, so an old SIM saved with dashes still matches.
        let number: String
    }

    struct Found: Hashable, Sendable {
        let candidate: Candidate
        /// The type the warning names: the class when a saved SIM has the same one, otherwise plain SIM.
        let name: DocumentType
    }

    /// Nil when there's nothing to compare: a type without a number, or a number with no digits.
    static func candidate(type: DocumentType, values: [String: String]) -> Candidate? {
        number(of: type, in: values).map { Candidate(type: type, number: $0) }
    }

    /// Nil when nothing matches or the list can't be read, so the save goes ahead. Throws only
    /// `VaultError.locked`, which drops the scan as a locked save does.
    static func find(_ candidate: Candidate, in store: any DocumentStoring) async throws -> Found? {
        var firstError: (any Error)?
        // One line per check at most: a line per unreadable document would tell how many there are.
        defer {
            if let firstError {
                Logger.scan.error("Duplicate check skipped: \(ErrorSummary.describe(firstError), privacy: .public)")
            }
        }
        let saved: [Document]
        do {
            saved = try await store.documents()
        } catch VaultError.locked {
            throw VaultError.locked
        } catch {
            firstError = error
            return nil
        }
        var classless: Found?
        for document in saved where canMatch(document.type, candidate.type) {
            let fields: DocumentFields
            do {
                fields = try await store.fields(of: document.id)
            } catch VaultError.locked {
                throw VaultError.locked
            } catch {
                firstError = firstError ?? error
                continue
            }
            guard number(of: document.type, in: fields.values) == candidate.number else { continue }
            if document.type == candidate.type { return Found(candidate: candidate, name: candidate.type) }
            classless = classless ?? Found(candidate: candidate, name: .sim)
        }
        return classless
    }

    /// The same type, or two SIMs where one has no class: its class wasn't read, so it may be either.
    private static func canMatch(_ saved: DocumentType, _ new: DocumentType) -> Bool {
        saved == new || (saved.isSIM && new.isSIM && (saved == .sim || new == .sim))
    }

    private static func number(of type: DocumentType, in values: [String: String]) -> String? {
        let key = DocumentFieldStyle.keys(for: type).first { $0 == FieldKey.nik || $0 == FieldKey.simNumber }
        guard let key, let number = values[key].map(DocumentNumber.init), !number.isEmpty else { return nil }
        return number.digits
    }
}
