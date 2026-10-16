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
        var needsCheck: Set<String> = []

        var number = ""
        var nikFromNextLine = false
        if let found = card.value(of: "NIK") {
            let (digits, corrected) = NIK.digits(from: found.text)
            number = digits
            fields[FieldKey.nik] = number
            nikFromNextLine = found.fromNextLine
            // A matching birth date confirms only digits 7 to 12, so a correction stays marked.
            if corrected { needsCheck.insert(FieldKey.nik) }
        }
        let nikDate = NIK.birthDate(in: number)
        if nikDate == nil { needsCheck.insert(FieldKey.nik) }
        if let nikDate, let woman = isWoman(card.value(of: "Jenis Kelamin")?.text), woman != nikDate.woman {
            needsCheck.insert(FieldKey.nik)
        }

        let name = card.value(of: "Nama")
        fields[FieldKey.name] = name?.text
        if name.map(nameNeedsCheck) ?? true { needsCheck.insert(FieldKey.name) }

        let birth = readBirthDate(card.value(of: "Tempat/Tgl Lahir"), nikDate: nikDate, today: today)
        if let date = birth.date { fields[FieldKey.birthDate] = date.string }
        if birth.needsCheck { needsCheck.insert(FieldKey.birthDate) }
        if nikFromNextLine && !birth.confirmed { needsCheck.insert(FieldKey.nik) }

        if let birth = birth.date, let nikDate, !nikDate.matches(birth) {
            needsCheck.formUnion([FieldKey.nik, FieldKey.birthDate])
        }
        // A KTP is valid for life, so it has no expiry.
        return ParsedDocument(type: .ktp, fields: DocumentFields(fields), expiry: nil, needsCheck: needsCheck)
    }

    /// Nothing confirms a name, so a guessed pairing, a possible second line or a misread character is
    /// marked; what a misread character should have been can't be known, so it isn't changed.
    private static func nameNeedsCheck(_ found: LabeledLines.Found) -> Bool {
        found.fromNextLine || found.continues || !found.text.looksLikeAName
    }

    /// The birth date, whether it needs checking, and whether the NIK confirms it. Two separate readings
    /// that agree confirm each other: a value from the next line, or a corrected date, is then no longer a
    /// guess.
    private static func readBirthDate(_ found: LabeledLines.Found?, nikDate: NIK.BirthDate?, today: CalendarDate) -> (
        date: CalendarDate?, needsCheck: Bool, confirmed: Bool
    ) {
        guard let read = found?.text.lastDateReadingLookalikes else { return (nil, true, false) }
        let confirmed = nikDate?.matches(read.date) ?? false
        // The NIK only holds the last two digits of the year, so a misread century passes the cross-check.
        let plausible = read.date.year >= 1900 && read.date <= today
        let guessed = found?.fromNextLine == true || read.corrected
        return (read.date, !plausible || (guessed && !confirmed), confirmed)
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
