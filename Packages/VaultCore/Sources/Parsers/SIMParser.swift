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
        var reasons: [String: Set<CheckReason>] = [:]

        let labeled = hasLabels(lines)
        let number = readNumber(in: lines, digits: expectedDigits(lines))
        let classEnd = classEnd(in: lines, labeled: labeled, numberLine: number.lines.min())
        let (type, classReasons) = simClass(in: lines[..<(classEnd ?? lines.endIndex)])
        var typeReasons = classReasons
        if classEnd == nil { typeReasons.insert(.classUnclear) }

        if let text = number.text { fields[FieldKey.simNumber] = text }
        let nikDate = number.nikDate

        let (name, birthText, birthLine) = nameAndBirth(
            in: lines, labeled: labeled, card: card, numberLine: number.lines.min())
        fields[FieldKey.name] = name?.text
        let read = birthText?.lastDateReadingLookalikes
        let birth = read?.date
        fields[FieldKey.birthDate] = birth?.string
        reasons[FieldKey.simNumber] = number.reasons
        reasons[FieldKey.name] = name.map(nameReasons) ?? [.notFound]
        reasons[FieldKey.birthDate] = birthReasons(read, number: number, today: today)

        if let nikDate {
            if let birth, !nikDate.matches(birth) {
                reasons[FieldKey.simNumber, default: []].insert(.disagreesWithBirthDate)
                reasons[FieldKey.birthDate, default: []].insert(.disagreesWithBirthDate)
            }
            if let woman = isWoman(sexField(in: lines)), woman != nikDate.woman {
                reasons[FieldKey.simNumber, default: []].insert(.sexDisagrees)
            }
        }

        var (expiry, expiryReasons) = readExpiry(
            in: lines, labeled: labeled, number: number, birth: (birthText, birthLine, birth), today: today)
        if isMixedLayout(labeled: labeled, digits: number.digits) {
            for key in [FieldKey.simNumber, FieldKey.name, FieldKey.birthDate] {
                reasons[key, default: []].insert(.mixedLayout)
            }
            typeReasons.insert(.mixedLayout)
            expiryReasons.insert(.mixedLayout)
        }

        return ParsedDocument(
            type: type, fields: DocumentFields(fields), expiry: expiry, reasons: reasons.filter { !$0.value.isEmpty },
            typeReasons: typeReasons, expiryReasons: expiryReasons)
    }

    private struct ReadNumber {
        var text: String?
        var reasons: Set<CheckReason> = [.notFound]
        /// Lookalike letters were swapped for digits.
        var corrected = false
        /// The date inside the number, when it's a NIK.
        var nikDate: NIK.BirthDate?
        /// Where it was read, so those lines aren't taken for the expiry.
        var lines: Set<Int> = []
        /// Its count of digits, which tells the layout whatever the stored format.
        var digits: Int?
    }

    private static func readNumber(in lines: [String], digits expected: Int?) -> ReadNumber {
        let numbers = lines.indices.compactMap { index in number(in: lines[index]).map { (index, $0) } }
        var read = ReadNumber(lines: Set(numbers.map(\.0)))
        guard let found = numbers.first?.1 else { return read }
        read.text = found.text
        read.digits = found.digits.count
        read.corrected = found.corrected
        read.reasons = []
        if found.corrected { read.reasons.insert(.lookalike) }
        if numbers.count > 1 { read.reasons.insert(.severalNumbers) }
        // A number that doesn't fit the layout is a sign of both layouts at once.
        if let expected, expected != found.digits.count { read.reasons.insert(.mixedLayout) }
        // From July 2024 the number is the holder's NIK, so it's checked like one.
        if found.digits.count == 16 {
            read.nikDate = NIK.birthDate(in: found.digits)
            if read.nikDate == nil { read.reasons.insert(.noDateInNumber) }
        }
        return read
    }

    private static func hasLabels(_ lines: [String]) -> Bool {
        lines.contains { line in labels.contains { LabeledLines.rest(after: $0, in: line) != nil } }
    }

    /// 16 on a card with labels, which has the NIK as its number, and 14 on an older card with numbered
    /// fields. nil when the layout can't be told.
    private static func expectedDigits(_ lines: [String]) -> Int? {
        let labeled = hasLabels(lines)
        let numbered = lines.contains { numberedField($0) != nil }
        guard labeled != numbered else { return nil }
        return labeled ? 16 : 14
    }

    /// The expiry has no label: it's the one date left once the number and the birth date are set aside.
    private static func readExpiry(
        in lines: [String], setAside: (Int) -> Bool, birth: CalendarDate?, today: CalendarDate
    ) -> (
        CalendarDate?, reasons: Set<CheckReason>
    ) {
        let candidates = lines.indices.filter { !setAside($0) }.flatMap { lines[$0].numericDates }
        guard let expiry = candidates.first else { return (nil, [.notFound]) }
        guard candidates.count == 1 else { return (nil, [.severalDates]) }
        // Without the birth date, its line can't be set aside, so the one date left may be the birth date.
        guard let birth else { return (expiry, [.expiryUnconfirmed]) }
        return (expiry, implausible(expiry, birth: birth, today: today) ? [.implausibleExpiry] : [])
    }

    /// A SIM is valid for five years from issue and needs its holder to be 17, so anything outside is a misread.
    private static func implausible(_ expiry: CalendarDate, birth: CalendarDate, today: CalendarDate) -> Bool {
        let date = (expiry.year, expiry.month, expiry.day)
        return date > (today.year + 5, today.month, today.day) || date < (birth.year + 17, birth.month, birth.day)
    }

    /// Where the name and the birth date are: by label on a newer card, and by order and shape on an older
    /// one, whose line numbers Vision drops or misreads.
    private static func nameAndBirth(in lines: [String], labeled: Bool, card: LabeledLines, numberLine: Int?) -> (
        name: LabeledLines.Found?, birthText: String?, birthLine: Int?
    ) {
        guard !labeled else {
            let birth = field(2, label: "Tempat, Tgl Lahir/Place, Date of Birth", in: lines, card: card)?.text
            return (field(1, label: "Nama/Name", in: lines, card: card), birth, nil)
        }
        let birthLine = oldBirthLine(in: lines, after: numberLine)
        return (oldName(in: lines, number: numberLine, birth: birthLine), birthLine.map { lines[$0] }, birthLine)
    }

    /// The expiry, by the rules of the card's layout.
    private static func readExpiry(
        in lines: [String], labeled: Bool, number: ReadNumber,
        birth: (text: String?, line: Int?, date: CalendarDate?), today: CalendarDate
    ) -> (CalendarDate?, reasons: Set<CheckReason>) {
        guard labeled else {
            return oldExpiry(in: lines, after: birth.line, setAside: number.lines, birth: birth.date, today: today)
        }
        let setAside = { (index: Int) in
            number.lines.contains(index) || (birth.text.map(lines[index].contains) ?? false)
        }
        return readExpiry(in: lines, setAside: setAside, birth: birth.date, today: today)
    }

    /// Where the class can no longer be, so a blood type further down is never taken for one: a newer card
    /// prints it above the name label, an older one above its number, or else above field 1, which Vision
    /// may drop.
    private static func classEnd(in lines: [String], labeled: Bool, numberLine: Int?) -> Int? {
        guard !labeled else { return lines.firstIndex { LabeledLines.rest(after: "Nama/Name", in: $0) != nil } }
        return numberLine ?? lines.firstIndex { numberedField($0)?.number == 1 }
    }

    /// Signs of both layouts at once, a 14-digit number with labels or a NIK without: the rules aren't
    /// mixed, and every field, the expiry included, is left to the user.
    private static func isMixedLayout(labeled: Bool, digits: Int?) -> Bool {
        (labeled && digits == 14) || (!labeled && digits == 16)
    }

    /// A field number read alone on its line, with or without its dot: "1.", "2", "3 ,".
    private static func isFieldNumber(_ line: String) -> Bool {
        line.wholeMatch(of: /[1-6]\s*[.,]?/) != nil
    }

    /// A line with no letter and no digit, like "~": noise Vision read, never part of a field. Told by
    /// that alone, never by length, so a short name stays a name.
    private static func isNoise(_ line: String) -> Bool {
        !line.contains { $0.isLetter || $0.isNumber }
    }

    /// The birth line on an older card: field 2, or else the first line after the number shaped
    /// "PLACE, dd-mm-yyyy", the comma optional. A place and date split over two lines isn't one.
    private static func oldBirthLine(in lines: [String], after numberLine: Int?) -> Int? {
        if let index = lines.firstIndex(where: { numberedField($0)?.number == 2 }),
            lines[index].lastDateReadingLookalikes != nil
        {
            return index
        }
        let start = (numberLine ?? -1) + 1
        guard start < lines.count else { return nil }
        return (start..<lines.count).first { index in
            let line = lines[index]
            return line.contains(where: \.isLetter) && line.last?.isNumber == true
                && line.lastDateReadingLookalikes != nil
        }
    }

    /// The name on an older card: field 1, or else the one line between the number and the birth line.
    /// `continues` is set for more than one line, and `misread` for a line number removed from "1BUDI" or
    /// "I. BUDI". Without the number or the birth line, nothing is guessed.
    private static func oldName(in lines: [String], number: Int?, birth: Int?) -> LabeledLines.Found? {
        // A "1." counts only between the number and the birth line, or above a birth line when the number
        // wasn't read: the back of a card numbers its rules too, and they have no birth line.
        let start = number.map { $0 + 1 } ?? 0
        let end = birth ?? (number == nil ? start : lines.endIndex)
        if start < end, let index = (start..<end).first(where: { numberedField(lines[$0])?.number == 1 }),
            let text = numberedField(lines[index])?.text, !text.isEmpty
        {
            // The next real line belongs to the name when it isn't a numbered field or the birth line.
            let next = lines.indices.dropFirst(index + 1).first { !isNoise(lines[$0]) }
            let continues =
                next.map { $0 != birth && numberedField(lines[$0]) == nil && !isFieldNumber(lines[$0]) } ?? false
            return LabeledLines.Found(text: text, continues: continues)
        }
        guard let number, let birth, birth > number + 1 else { return nil }
        let between = lines[(number + 1)..<birth].filter { !isNoise($0) }
        // A field number read alone on its line ("1.", "2.") is no part of the name, but it's a misread.
        let bareNumbers = between.filter(isFieldNumber)
        var corrected = !bareNumbers.isEmpty
        let candidates = between.filter { !isFieldNumber($0) }.map { line in
            guard let match = line.wholeMatch(of: /(?:1(?=[A-Z])|[Il|1]\s*[.,])\s*(.*)/) else { return line }
            corrected = true
            return String(match.1)
        }
        .filter { !$0.isEmpty }
        guard !candidates.isEmpty else { return nil }
        return LabeledLines.Found(
            text: candidates.joined(separator: " "), continues: candidates.count > 1, misread: corrected)
    }

    /// The expiry on an older card: the one line after the birth line that's only a date.
    private static func oldExpiry(
        in lines: [String], after birthLine: Int?, setAside: Set<Int>, birth: CalendarDate?, today: CalendarDate
    ) -> (CalendarDate?, reasons: Set<CheckReason>) {
        guard let birthLine, let birth, birthLine + 1 < lines.count else { return (nil, [.notFound]) }
        let candidates = ((birthLine + 1)..<lines.count)
            .filter { !setAside.contains($0) && !lines[$0].contains(where: \.isLetter) }
            .flatMap { lines[$0].numericDates }
        guard let expiry = candidates.first else { return (nil, [.notFound]) }
        guard candidates.count == 1 else { return (nil, [.severalDates]) }
        return (expiry, implausible(expiry, birth: birth, today: today) ? [.implausibleExpiry] : [])
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
        // Stored as digits alone, however it was printed; dashes are for display only.
        case 14: return Number(text: digits, digits: digits, corrected: corrected)
        default: return nil
        }
    }

    private static let classes: [String: DocumentType] = [
        "A": .simA, "BI": .simB1, "BII": .simB2, "C": .simC, "CI": .simC1, "CII": .simC2, "D": .simD, "DI": .simD1,
        "AUMUM": .simAUmum, "BIUMUM": .simB1Umum, "BIIUMUM": .simB2Umum,
    ]

    /// The class as printed ("BI", "A UMUM"), with a 1, l or | read for an I. A correction, or no single
    /// class, is marked so the user picks it.
    private static func simClass(in lines: ArraySlice<String>) -> (type: DocumentType, reasons: Set<CheckReason>) {
        var found: [DocumentType: Bool] = [:]
        for line in lines {
            let squeezed = line.uppercased().filter { $0 != " " }
            guard let match = squeezed.wholeMatch(of: /([ABCD])([I1L|]{0,2})(UMUM)?/) else { continue }
            let marks = String(match.2)
            let numerals = marks.replacing(/[1L|]/, with: "I")
            guard let type = classes[String(match.1) + numerals + (match.3.map(String.init) ?? "")] else { continue }
            found[type] = (found[type] ?? false) || marks != numerals
        }
        guard found.count == 1, let (type, corrected) = found.first else { return (.sim, [.classUnclear]) }
        return (type, corrected ? [.lookalike] : [])
    }

    /// On a card with labels: the rest of the "Jenis Kelamin/Sex" line and the values under it, up to the
    /// address, skipping the blood type label beside it. An older card's sex is never needed: its number
    /// isn't a NIK, and a 16-digit number on it is marked anyway.
    private static func sexField(in lines: [String]) -> String {
        guard let start = lines.firstIndex(where: { LabeledLines.rest(after: "Jenis Kelamin/Sex", in: $0) != nil })
        else { return "" }
        let isLabel = { (line: String) in labels.contains { LabeledLines.rest(after: $0, in: line) != nil } }
        let below = lines[(start + 1)...].prefix { LabeledLines.rest(after: "Alamat/Address", in: $0) == nil }
        let rest = LabeledLines.rest(after: "Jenis Kelamin/Sex", in: lines[start]) ?? ""
        return ([rest] + below.filter { !isLabel($0) }).joined(separator: " ")
    }

    /// From PRIA or WANITA, the words every SIM uses. nil when neither, or both, can be read.
    private static func isWoman(_ text: String) -> Bool? {
        let text = text.uppercased()
        let man = text.contains(/\bPRIA\b/)
        let woman = text.contains(/\bWANITA\b/)
        return man == woman ? nil : woman
    }
}

// Why a value is marked, for the review screen.
extension SIMParser {
    /// A misread character is only marked, since what it should have been can't be known.
    private static func nameReasons(_ name: LabeledLines.Found) -> Set<CheckReason> {
        var reasons: Set<CheckReason> = name.continues ? [.mayContinue] : []
        if name.misread || !name.text.looksLikeAName { reasons.insert(.oddCharacters) }
        return reasons
    }

    /// A corrected date is a guess, unless a new card's number, the NIK, agrees with it. A corrected number
    /// confirms nothing: the same misread letter could be in both.
    private static func birthReasons(
        _ read: (date: CalendarDate, corrected: Bool)?, number: ReadNumber, today: CalendarDate
    ) -> Set<CheckReason> {
        guard let read else { return [.notFound] }
        // A NIK only holds the last two digits of the year, and an old number holds none.
        var reasons: Set<CheckReason> = read.date.year < 1900 || read.date > today ? [.impossibleDate] : []
        let confirmed = !number.corrected && number.nikDate?.matches(read.date) == true
        if read.corrected && !confirmed { reasons.insert(.lookalike) }
        return reasons
    }
}
