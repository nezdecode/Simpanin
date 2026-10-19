//
//  KTPParser.swift
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

/// Reads a KTP from its recognised text lines. It fills in what it can and marks what the user
/// should look at again; it never guesses silently.
public enum KTPParser {
    /// nil when the lines don't look like a KTP: there's no NIK label.
    public static func parse(_ lines: [String], today: CalendarDate) -> ParsedDocument? {
        let card = LabeledLines(lines: lines, labels: labels)
        guard card.contains("NIK") else { return nil }
        var fields: [String: String] = [:]
        var reasons: [String: Set<CheckReason>] = [:]

        var number = ""
        var nikFromNextLine = false
        var nikCorrected = false
        if let found = card.value(of: "NIK") {
            let (digits, corrected) = NIK.digits(from: found.text)
            number = digits
            fields[FieldKey.nik] = number
            nikFromNextLine = found.fromNextLine
            nikCorrected = corrected
            // A matching birth date confirms only digits 7 to 12, so a correction stays marked.
            if corrected { reasons[FieldKey.nik, default: []].insert(.lookalike) }
        }
        let nikDate = NIK.birthDate(in: number)
        // A NIK of the wrong length, or with a letter left, is refused by the review screen instead.
        if number.isEmpty {
            reasons[FieldKey.nik, default: []].insert(.notFound)
        } else if nikDate == nil, number.count == 16, number.allSatisfy(\.isASCIIDigit) {
            reasons[FieldKey.nik, default: []].insert(.noDateInNumber)
        }
        if let nikDate, let woman = isWoman(card.value(of: "Jenis Kelamin")?.text), woman != nikDate.woman {
            reasons[FieldKey.nik, default: []].insert(.sexDisagrees)
        }

        let name = card.value(of: "Nama")
        fields[FieldKey.name] = name?.text
        reasons[FieldKey.name] = name.map(nameReasons) ?? [.notFound]

        // The same misread letter in the NIK and the date gives two wrong values that agree, so a corrected
        // NIK confirms nothing.
        let birth = readBirthDate(
            card.value(of: "Tempat/Tgl Lahir"), nikDate: nikCorrected ? nil : nikDate, today: today)
        if let date = birth.date { fields[FieldKey.birthDate] = date.string }
        reasons[FieldKey.birthDate] = birth.reasons
        if nikFromNextLine && !birth.confirmed { reasons[FieldKey.nik, default: []].insert(.readFromAnotherLine) }

        if let birth = birth.date, let nikDate, !nikDate.matches(birth) {
            reasons[FieldKey.nik, default: []].insert(.disagreesWithBirthDate)
            reasons[FieldKey.birthDate, default: []].insert(.disagreesWithBirthDate)
        }
        let confirmed =
            birth.confirmed && !birth.corrected && reasons[FieldKey.nik, default: []].isEmpty
            && reasons[FieldKey.birthDate, default: []].isEmpty
        // A KTP is valid for life, so it has no expiry.
        return ParsedDocument(
            type: .ktp, fields: DocumentFields(fields), expiry: nil, reasons: reasons.filter { !$0.value.isEmpty },
            birthDateConfirmed: confirmed)
    }

    /// Nothing confirms a name, so a guessed pairing, a possible second line or a misread character is
    /// marked; what a misread character should have been can't be known, so it isn't changed.
    private static func nameReasons(_ found: LabeledLines.Found) -> Set<CheckReason> {
        var reasons: Set<CheckReason> = []
        if found.fromNextLine { reasons.insert(.readFromAnotherLine) }
        if found.continues { reasons.insert(.mayContinue) }
        if !found.text.looksLikeAName { reasons.insert(.oddCharacters) }
        return reasons
    }

    /// The birth date, why it needs checking, and whether the NIK confirms it. Two separate readings that
    /// agree confirm each other: a value from the next line, or a corrected date, is then no longer a guess.
    private static func readBirthDate(_ found: LabeledLines.Found?, nikDate: NIK.BirthDate?, today: CalendarDate) -> (
        date: CalendarDate?, reasons: Set<CheckReason>, confirmed: Bool, corrected: Bool
    ) {
        guard let found, let read = found.text.lastDateReadingLookalikes else {
            return (nil, [.notFound], false, false)
        }
        let confirmed = nikDate?.matches(read.date) ?? false
        var reasons: Set<CheckReason> = []
        // The NIK only holds the last two digits of the year, so a misread century passes the cross-check.
        if read.date.year < 1900 || read.date > today { reasons.insert(.impossibleDate) }
        if !confirmed {
            if found.fromNextLine { reasons.insert(.readFromAnotherLine) }
            if read.corrected { reasons.insert(.lookalike) }
        }
        return (read.date, reasons, confirmed, read.corrected)
    }

    /// Every label on the front of a KTP, so a label line is never taken as another label's value.
    private static let labels = [
        "NIK", "Nama", "Tempat/Tgl Lahir", "Jenis Kelamin", "Gol Darah", "Alamat", "RT/RW", "Kel/Desa", "Kecamatan",
        "Agama", "Status Perkawinan", "Pekerjaan", "Kewarganegaraan", "Berlaku Hingga",
    ]

    /// From "Jenis Kelamin", which shares its line with "Gol. Darah". nil when it can't be read.
    private static func isWoman(_ text: String?) -> Bool? {
        guard let text = text?.uppercased() else { return nil }
        if text.contains("PEREMPUAN") { return true }
        if text.contains("LAKI") { return false }
        return nil
    }
}
