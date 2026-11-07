//
//  DocumentForm.swift
//  Simpanin
//
//  Created by Inez Amanda on 5/11/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import Parsers
import VaultCore

/// A document's fields while they're checked, after a scan or in an edit: the text of each, why one is
/// marked "Periksa lagi", and why Simpan refuses one.
nonisolated struct DocumentForm: Equatable, Sendable {
    enum FieldProblem: Equatable, Sendable {
        case notADate
        case birthDateInFuture
        case nikLength
    }

    /// What shows under a value. A refusal replaces a mark: it's what has to change before Simpan works.
    enum Note: Equatable, Sendable {
        case refusal(FieldProblem)
        /// "Periksa lagi", with the first reason when one is known.
        case mark(CheckReason?)
        /// The expiry was read or picked for a kind of document whose date means something else.
        case dateFromAnotherType
    }

    /// The type chosen now; its keys are the fields shown.
    var type: DocumentType
    /// The type the values were read or saved as. Marks about the number and the layout belong to it.
    private(set) var loadedType: DocumentType
    /// The text of each field, by `FieldKey`, as read, stored or typed.
    private(set) var values: [String: String]
    /// Why each field is marked "Periksa lagi". Every reason is kept, so fixing one never hides another;
    /// the first is the one shown.
    private(set) var marked: [String: Set<CheckReason>]
    /// Why Simpan refused a field, shown under it until the field is edited.
    private(set) var problems: [String: FieldProblem] = [:]
    /// The values as the form opened with them, as shown: what a change is measured against.
    let original: [String: String]
    /// A saved document's fields as stored, for an edit; nil after a scan.
    let stored: [String: String]?

    /// After a scan: the values as read, with the parser's marks.
    init(type: DocumentType = .other, values: [String: String] = [:], marked: [String: Set<CheckReason>] = [:]) {
        self.type = type
        loadedType = type
        self.values = values
        self.marked = marked
        original = values
        stored = nil
    }

    /// A saved document, to edit. Nothing is marked: the parser's marks were never stored.
    init(type: DocumentType, stored: DocumentFields) {
        let shown = stored.values.reduce(into: [String: String]()) { shown, field in
            shown[field.key] =
                FieldDates.dateKeys.contains(field.key) ? DocumentFieldStyle.dayFirst(field.value) : field.value
        }
        self.type = type
        loadedType = type
        values = shown
        marked = [:]
        original = shown
        self.stored = stored.values
    }

    /// The fields whose text differs from what the form opened with. An empty field and a missing one are
    /// the same, so a field typed in and cleared again isn't a change.
    var changedKeys: Set<String> {
        Set(values.keys).union(original.keys).filter { (values[$0] ?? "") != (original[$0] ?? "") }
    }

    /// The NIK was there when the form opened and isn't now; one that was never filled in isn't asked about
    /// again.
    var nikEmptied: Bool {
        nikMissing && !Self.trimmed(original[FieldKey.nik]).isEmpty
    }

    /// What Simpan stores. After a scan, every filled field, trimmed and with dates year first. In an edit,
    /// a field nobody changed is stored exactly as it was, even one today's checks would refuse, and a key
    /// the type doesn't show stays.
    func savedFields() -> [String: String] {
        var fields = stored ?? [:]
        for key in fieldKeys where stored == nil || changedKeys.contains(key) {
            let text = Self.trimmed(values[key])
            fields[key] = text.isEmpty ? nil : FieldDates.dateKeys.contains(key) ? FieldDates.yearFirst(text) : text
        }
        return fields
    }

    /// The fields the chosen type has, in the order the screen shows them.
    var fieldKeys: [String] { DocumentFieldStyle.keys(for: type) }

    /// The field whose digits hold the birth date: a KTP's NIK, or a SIM's number.
    var numberKey: String? { fieldKeys.first { $0 == FieldKey.nik || $0 == FieldKey.simNumber } }

    /// A KTP saved without its NIK is asked about first, never refused: an old photo can be blurred there.
    var nikMissing: Bool { fieldKeys.contains(FieldKey.nik) && Self.trimmed(values[FieldKey.nik]).isEmpty }

    /// False when the text is what the field already held: a field writes its value back when it takes
    /// focus, and that isn't an edit, so its reason stays.
    @discardableResult
    mutating func setValue(_ text: String, for key: String) -> Bool {
        let text = FieldDates.dateKeys.contains(key) ? FieldDates.typedDate(text) : text
        guard text != values[key] ?? "" else { return false }
        values[key] = text
        // The user looked at it and decided, so it's no longer the parser's guess.
        marked[key] = nil
        problems[key] = nil
        // A complete date is judged at once; a half-typed one only when Simpan is tapped.
        if FieldDates.dateKeys.contains(key), let typed = values[key], typed.count == "dd-mm-yyyy".count {
            problems[key] = Self.problem(with: typed, for: key)
        }
        if key == numberKey || key == FieldKey.birthDate { checkNumberAgainstBirthDate() }
        return true
    }

    /// The field lost focus, so typing is done: a filled one is judged now.
    mutating func fieldLeft(_ key: String) {
        let text = Self.trimmed(values[key])
        guard !text.isEmpty else { return }
        problems[key] = Self.problem(with: text, for: key)
    }

    /// Judges every filled field, shows each one's reason, and returns the first wrong one in screen order.
    mutating func firstProblem() -> String? {
        firstProblem(among: Set(fieldKeys))
    }

    /// Shows every filled field's reason, but returns only the first wrong one among `keys`: an edit is
    /// blocked by the fields it changed, never by a value stored before today's checks.
    mutating func firstProblem(among keys: Set<String>) -> String? {
        var first: String?
        for key in fieldKeys {
            let text = Self.trimmed(values[key])
            guard !text.isEmpty, let problem = Self.problem(with: text, for: key) else { continue }
            problems[key] = problem
            if keys.contains(key) { first = first ?? key }
        }
        return first
    }

    func note(for key: String) -> Note? {
        if let problem = problems[key] { return .refusal(problem) }
        var reasons = marked[key] ?? []
        // These speak of the loaded document's number and layout, which another kind of document doesn't have.
        if Self.dateKind(type) != Self.dateKind(loadedType) {
            reasons.subtract([.disagreesWithBirthDate, .mixedLayout])
        }
        return reasons.min().map(Note.mark)
    }

    /// The parsers' cross-check, again after an edit: a NIK, or a new SIM's number, holds the birth date,
    /// and when they disagree either could be wrong. Only that reason changes; any other stays.
    private mutating func checkNumberAgainstBirthDate() {
        guard let number = numberKey,
            let birth = FieldDates.yearFirst(values[FieldKey.birthDate] ?? "").flatMap(CalendarDate.init),
            // Dashes and spaces are only for display. An old SIM's 14 digits hold no date, so they give nil.
            let agrees = NIK.agrees(
                values[number, default: ""].filter(\.isASCIIDigit), withBirthDate: birth)
        else {
            // One of them can't be compared any more, so the other no longer disagrees with anything.
            for key in [numberKey, FieldKey.birthDate].compactMap(\.self) { drop(.disagreesWithBirthDate, from: key) }
            return
        }
        for key in [number, FieldKey.birthDate] {
            if agrees {
                drop(.disagreesWithBirthDate, from: key)
            } else {
                marked[key, default: []].insert(.disagreesWithBirthDate)
            }
        }
    }

    private mutating func drop(_ reason: CheckReason, from key: String) {
        marked[key]?.remove(reason)
        if marked[key]?.isEmpty == true { marked[key] = nil }
    }
}

nonisolated extension DocumentForm {
    /// A label shows in the list without opening the document, so it must not hold a number.
    static func looksLikeANumber(_ label: String) -> Bool { label.filter(\.isNumber).count >= 8 }

    static func trimmed(_ text: String?) -> String {
        text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// What a document's date means: every SIM class shares one meaning, an STNK's is its tax.
    static func dateKind(_ type: DocumentType) -> String {
        type.isSIM ? "sim" : type.rawValue
    }

    /// Why a value can't be stored, or nil when it can. Only a NIK's length and dates are judged.
    static func problem(with text: String, for key: String) -> FieldProblem? {
        if key == FieldKey.nik {
            return NIK.isWellFormed(text) ? nil : .nikLength
        }
        guard FieldDates.dateKeys.contains(key) else { return nil }
        guard let date = FieldDates.yearFirst(text).flatMap(CalendarDate.init) else { return .notADate }
        return key == FieldKey.birthDate && date > .today ? .birthDateInFuture : nil
    }
}
