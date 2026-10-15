//
//  SIMParser.swift
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

/// Reads a SIM from its recognised text lines, in both card formats: the older one with numbered
/// fields, and the one from July 2024 with bilingual labels and the NIK as its number.
public enum SIMParser {
    /// nil when the lines don't look like a SIM.
    public static func parse(_ lines: [String], today: CalendarDate) -> ParsedDocument? {
        let lines = lines.map { $0.trimmingCharacters(in: .whitespaces) }
        guard lines.contains(where: isTitle) else { return nil }
        let card = LabeledLines(lines: lines, labels: labels)
        var fields: [String: String] = [:]
        var needsCheck: Set<String> = []

        // The class is printed above the fields, so a blood type further down is never taken for one.
        let firstField = lines.firstIndex {
            numberedField($0)?.number == 1 || LabeledLines.rest(after: "Nama/Name", in: $0) != nil
        }
        let (type, typeNeedsCheck) = simClass(in: lines[..<(firstField ?? lines.endIndex)])

        let number = readNumber(in: lines, digits: expectedDigits(lines))
        if let text = number.text { fields[FieldKey.simNumber] = text }
        if number.needsCheck { needsCheck.insert(FieldKey.simNumber) }
        let nikDate = number.nikDate

        let name = field(1, label: "Nama/Name", in: lines, card: card)
        if let name {
            fields[FieldKey.name] = name.text
            // A misread character is only marked, since what it should have been can't be known.
            if name.continues || !name.text.looksLikeAName { needsCheck.insert(FieldKey.name) }
        } else {
            needsCheck.insert(FieldKey.name)
        }

        let birthText = field(2, label: "Tempat, Tgl Lahir/Place, Date of Birth", in: lines, card: card)?.text
        let birth = birthText?.lastDate
        if let birth {
            fields[FieldKey.birthDate] = birth.string
            // A NIK only holds the last two digits of the year, and an old number holds none.
            if birth.year < 1900 || birth > today { needsCheck.insert(FieldKey.birthDate) }
        } else {
            needsCheck.insert(FieldKey.birthDate)
        }

        if let nikDate {
            if let birth, !nikDate.matches(birth) { needsCheck.formUnion([FieldKey.simNumber, FieldKey.birthDate]) }
            if let woman = isWoman(lines), woman != nikDate.woman { needsCheck.insert(FieldKey.simNumber) }
        }

        let (expiry, expiryNeedsCheck) = readExpiry(
            in: lines, setAside: { number.lines.contains($0) || (birthText.map(lines[$0].contains) ?? false) },
            birth: birth, today: today)

        return ParsedDocument(
            type: type, fields: DocumentFields(fields), expiry: expiry, needsCheck: needsCheck,
            typeNeedsCheck: typeNeedsCheck, expiryNeedsCheck: expiryNeedsCheck)
    }

    /// The number, where it was read, and the date inside it when it's a NIK.
    private static func readNumber(in lines: [String], digits expected: Int?) -> (
        text: String?, needsCheck: Bool, nikDate: NIK.BirthDate?, lines: Set<Int>
    ) {
        let numbers = lines.indices.compactMap { index in number(in: lines[index]).map { (index, $0) } }
        let indices = Set(numbers.map(\.0))
        guard let found = numbers.first?.1 else { return (nil, true, nil, indices) }
        var needsCheck = found.corrected || numbers.count > 1 || (expected.map { $0 != found.digits.count } ?? false)
        // From July 2024 the number is the holder's NIK, so it's checked like one.
        var nikDate: NIK.BirthDate?
        if found.digits.count == 16 {
            nikDate = NIK.birthDate(in: found.digits)
            if nikDate == nil { needsCheck = true }
        }
        return (found.text, needsCheck, nikDate, indices)
    }

    /// 16 on a card with labels, which has the NIK as its number, and 14 on an older card with numbered
    /// fields. nil when the layout can't be told.
    private static func expectedDigits(_ lines: [String]) -> Int? {
        let labeled = lines.contains { line in labels.contains { LabeledLines.rest(after: $0, in: line) != nil } }
        let numbered = lines.contains { numberedField($0) != nil }
        guard labeled != numbered else { return nil }
        return labeled ? 16 : 14
    }

    /// The expiry has no label: it's the one date left once the number and the birth date are set aside.
    private static func readExpiry(
        in lines: [String], setAside: (Int) -> Bool, birth: CalendarDate?, today: CalendarDate
    ) -> (
        CalendarDate?, needsCheck: Bool
    ) {
        let candidates = lines.indices.filter { !setAside($0) }.flatMap { lines[$0].numericDates }
        guard candidates.count == 1, let expiry = candidates.first else { return (nil, true) }
        // Without the birth date, its line can't be set aside, so the one date left may be the birth date.
        guard let birth else { return (expiry, true) }
        let date = (expiry.year, expiry.month, expiry.day)
        // A SIM is valid for five years from issue and needs its holder to be 17, so anything outside is a misread.
        return (
            expiry, date > (today.year + 5, today.month, today.day) || date < (birth.year + 17, birth.month, birth.day)
        )
    }

    /// The labels on a card from July 2024. Older cards number their fields instead.
    private static let labels = [
        "Nama/Name", "Tempat, Tgl Lahir/Place, Date of Birth", "Gol Darah/Blood Type", "Jenis Kelamin/Sex",
        "Alamat/Address", "Pekerjaan/Occupation", "Diterbitkan Oleh/Issued by",
    ]

    private static func isTitle(_ line: String) -> Bool {
        let squeezed = line.uppercased().filter { $0 != " " }
        return squeezed.contains("SURATIZINMENGEMUDI") || squeezed.contains("DRIVINGLICENSE")
    }

    /// "1. BUDI CONTOH" on an older card.
    private static func numberedField(_ line: String) -> (number: Int, text: String)? {
        guard let match = line.wholeMatch(of: /([1-6])\s*[.,]\s*(.*)/) else { return nil }
        return (Int(match.1)!, String(match.2).trimmingCharacters(in: .whitespaces))
    }

    /// A field by its number on an older card, or by its label on a newer one.
    private static func field(_ number: Int, label: String, in lines: [String], card: LabeledLines) -> LabeledLines
        .Found?
    {
        if let index = lines.firstIndex(where: { numberedField($0)?.number == number }),
            let text = numberedField(lines[index])?.text, !text.isEmpty
        {
            // The next line belongs to this field when it isn't the next numbered one.
            let continues = index + 1 < lines.count && numberedField(lines[index + 1]) == nil
            return LabeledLines.Found(text: text, continues: continues)
        }
        return card.value(of: label)
    }

    private struct Number {
        var text: String
        var digits: String
        var corrected: Bool
    }

    /// 16 digits (the NIK, from July 2024) or 14 digits printed as 4-4-6 (older cards).
    private static func number(in line: String) -> Number? {
        let (digits, corrected) = NIK.digits(from: line.filter { $0 != "-" })
        guard digits.allSatisfy(\.isASCIIDigit) else { return nil }
        switch digits.count {
        case 16: return Number(text: digits, digits: digits, corrected: corrected)
        case 14:
            let parts = [digits.prefix(4), digits.dropFirst(4).prefix(4), digits.dropFirst(8)]
            return Number(text: parts.joined(separator: "-"), digits: digits, corrected: corrected)
        default: return nil
        }
    }

    private static let classes: [String: DocumentType] = [
        "A": .simA, "BI": .simB1, "BII": .simB2, "C": .simC, "CI": .simC1, "CII": .simC2, "D": .simD, "DI": .simD1,
        "AUMUM": .simAUmum, "BIUMUM": .simB1Umum, "BIIUMUM": .simB2Umum,
    ]

    /// The class as printed ("BI", "A UMUM"), with a 1, l or | read for an I. A correction, or no single
    /// class, is marked so the user picks it.
    private static func simClass(in lines: ArraySlice<String>) -> (DocumentType, needsCheck: Bool) {
        var found: [DocumentType: Bool] = [:]
        for line in lines {
            let squeezed = line.uppercased().filter { $0 != " " }
            guard let match = squeezed.wholeMatch(of: /([ABCD])([I1L|]{0,2})(UMUM)?/) else { continue }
            let marks = String(match.2)
            let numerals = marks.replacing(/[1L|]/, with: "I")
            guard let type = classes[String(match.1) + numerals + (match.3.map(String.init) ?? "")] else { continue }
            found[type] = (found[type] ?? false) || marks != numerals
        }
        guard found.count == 1, let (type, corrected) = found.first else { return (.sim, true) }
        return (type, corrected)
    }

    /// From PRIA or WANITA, the words every SIM uses. nil when neither, or both, can be read.
    private static func isWoman(_ lines: [String]) -> Bool? {
        let text = lines.joined(separator: " ").uppercased()
        let man = text.contains(/\bPRIA\b/)
        let woman = text.contains(/\bWANITA\b/)
        return man == woman ? nil : woman
    }
}
