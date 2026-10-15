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
        if let found = card.value(of: "NIK") {
            let (digits, corrected) = NIK.digits(from: found.text)
            number = digits
            fields[FieldKey.nik] = number
            if found.fromNextLine || corrected { needsCheck.insert(FieldKey.nik) }
        }
        let nikDate = NIK.birthDate(in: number)
        if nikDate == nil { needsCheck.insert(FieldKey.nik) }
        if let nikDate, let woman = isWoman(card.value(of: "Jenis Kelamin")?.text), woman != nikDate.woman {
            needsCheck.insert(FieldKey.nik)
        }

        if let found = card.value(of: "Nama") {
            fields[FieldKey.name] = found.text
            // A misread character is only marked, since what it should have been can't be known.
            if found.fromNextLine || found.continues || !found.text.looksLikeAName {
                needsCheck.insert(FieldKey.name)
            }
        } else {
            needsCheck.insert(FieldKey.name)
        }

        let birthText = card.value(of: "Tempat/Tgl Lahir")
        let birth = birthText?.text.lastDate
        if let birth {
            fields[FieldKey.birthDate] = birth.string
            // The NIK only holds the last two digits of the year, so a misread century passes the cross-check.
            let plausible = birth.year >= 1900 && birth <= today
            if birthText?.fromNextLine == true || !plausible { needsCheck.insert(FieldKey.birthDate) }
        } else {
            needsCheck.insert(FieldKey.birthDate)
        }

        if let birth, let nikDate, !nikDate.matches(birth) {
            needsCheck.formUnion([FieldKey.nik, FieldKey.birthDate])
        }
        // A KTP is valid for life, so it has no expiry.
        return ParsedDocument(type: .ktp, fields: DocumentFields(fields), expiry: nil, needsCheck: needsCheck)
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
