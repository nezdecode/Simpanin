//
//  ReviewModel.swift
//  Simpanin
//
//  Created by Inez Amanda on 16/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import CoreGraphics
import Foundation
import OSLog
import Observation
import Parsers
import VaultCore

/// "Periksa data": what a scan read, for the user to check and correct before it's saved. Everything
/// stays in memory until "Simpan ke vault".
@MainActor @Observable
final class ReviewModel {
    private(set) var pages: [CGImage] = []
    /// Set by the type sheet; picking one is the user's decision, so the parser's doubt goes. `load` sets
    /// the reasons again after setting the type.
    var type = DocumentType.other {
        didSet { typeReasons = [] }
    }
    var label = ""
    /// The text of each field, by `FieldKey`, as read or as typed.
    private(set) var values: [String: String] = [:]
    /// Why each field is marked "Periksa lagi". Every reason is kept, so fixing one never hides another;
    /// the first is the one shown.
    private(set) var marked: [String: Set<CheckReason>] = [:]
    private(set) var typeReasons: Set<CheckReason> = []
    private(set) var expiry: CalendarDate?
    private(set) var expiryReasons: Set<CheckReason> = []
    /// The type the expiry was read or picked for: on another kind of document the date means something
    /// else (an STNK's is its tax).
    private var expiryType = DocumentType.other
    /// Fields the user typed in, so a value typed back never counts as the scan's.
    private var edited: Set<String> = []
    private var birthDateConfirmed = false
    /// How the scan's pages relate; reasons only, no values from another person's card.
    private var reading: ScanReading?
    /// Why Simpan refused a field, shown under it until the field is edited.
    private(set) var problems: [String: FieldProblem] = [:]
    var saveError: RecoveryScreen?
    private(set) var saving = false
    /// An alert from Simpan is up, or about to follow another.
    private var asking = false
    /// Found by the check on Simpan; Simpan asks nothing until its alert is answered.
    private(set) var duplicate: DuplicateCheck.Found?
    /// Simpan in the duplicate alert, kept while the number and type stay the same, also after a failed save.
    private var acceptedDuplicate: DuplicateCheck.Candidate?
    /// What the pages alert said when it was answered; while the notes say the same, it isn't asked again.
    private var answeredPages: PageNotes?
    /// What the scan read, to tell what the user changed.
    private var scanned: [String: String] = [:]
    private var scannedType = DocumentType.other
    private var scannedExpiry: CalendarDate?

    private let store: any DocumentStoring
    private let encode: @Sendable (CGImage) -> Data?

    init(store: any DocumentStoring, encode: @escaping @Sendable (CGImage) -> Data? = PageEncoding.jpeg) {
        self.store = store
        self.encode = encode
    }

    /// Worked out each time from the reading and the type chosen now, never stored.
    var pageNotes: PageNotes { PageNotes(reading: reading, pageCount: pages.count, chosen: type) }

    /// The fields the chosen type has, in the order the screen shows them.
    var fieldKeys: [String] { Self.fieldKeys(for: type) }

    /// Only the types a parser reads have fields to check; the others have none yet.
    nonisolated static func fieldKeys(for type: DocumentType) -> [String] {
        if type == .ktp { return [FieldKey.nik, FieldKey.name, FieldKey.birthDate] }
        if type.isSIM { return [FieldKey.simNumber, FieldKey.name, FieldKey.birthDate] }
        return []
    }

    /// SIM, Paspor and STNK have a printed expiry to show and edit here; a KTP is valid for life.
    var hasExpiry: Bool { ExpiryText.hasPrintedExpiry(type) }

    /// The type has an expiry and none was read or picked: shown as "Belum diisi", marked, never as today.
    var expiryMissing: Bool { hasExpiry && expiry == nil }

    /// Only a SIM's parser should have read the date; Paspor and STNK have none yet, so an empty date there
    /// isn't a misread and gets no "Periksa lagi".
    var marksMissingExpiry: Bool { expiryMissing && type.isSIM }

    /// A label shows in the list without opening the document, so it must not hold a number.
    var labelLooksLikeANumber: Bool { label.filter(\.isNumber).count >= 8 }

    /// The user changed something the scan read, a field, the type or the expiry; a new scan would
    /// replace it.
    var hasUserChanges: Bool { values != scanned || type != scannedType || expiry != scannedExpiry }

    /// After a scan or a rescan: every field comes from the new pages. The label stays.
    func load(_ result: ParsedDocument?, pages: [CGImage], reading: ScanReading? = nil) {
        self.pages = pages
        // Always replaced, so a rescan that failed never keeps the old scan's notes.
        self.reading = reading
        // An alert that was about to follow Simpan saja belongs to the old pages, as do the answers.
        asking = false
        duplicate = nil
        acceptedDuplicate = nil
        answeredPages = nil
        type = result?.type ?? .other
        values = (result?.fields.values ?? [:]).reduce(into: [:]) { shown, field in
            shown[field.key] = Self.dateKeys.contains(field.key) ? Self.dayFirst(field.value) : field.value
        }
        scanned = values
        scannedType = type
        scannedExpiry = result?.expiry
        marked = result?.reasons ?? [:]
        typeReasons = result?.typeReasons ?? [.noDocumentRecognized]
        expiry = result?.expiry
        expiryType = type
        expiryReasons = result?.expiryReasons ?? []
        birthDateConfirmed = result?.birthDateConfirmed ?? false
        edited = []
        problems = [:]
        // A wrong value the scan read shows its reason at once, not only when Simpan is tapped.
        _ = firstProblem()
        saveError = nil
    }

    func setValue(_ text: String, for key: String) {
        let text = Self.dateKeys.contains(key) ? Self.typedDate(text) : text
        // A field writes its value back when it takes focus; that isn't an edit, and its reason stays.
        guard text != values[key] ?? "" else { return }
        values[key] = text
        edited.insert(key)
        // The user looked at it and decided, so it's no longer the parser's guess.
        marked[key] = nil
        problems[key] = nil
        // A complete date is judged at once; a half-typed one only when Simpan is tapped.
        if Self.dateKeys.contains(key), let typed = values[key], typed.count == "dd-mm-yyyy".count {
            problems[key] = Self.problem(with: typed, for: key)
        }
        if key == numberKey || key == FieldKey.birthDate { checkNumberAgainstBirthDate() }
    }

    /// The parsers' cross-check, again after an edit: a NIK, or a new SIM's number, holds the birth date,
    /// and when they disagree either could be wrong. Only that reason changes; any other stays.
    private func checkNumberAgainstBirthDate() {
        guard let number = numberKey,
            let birth = Self.yearFirst(values[FieldKey.birthDate] ?? "").flatMap(CalendarDate.init),
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

    private func drop(_ reason: CheckReason, from key: String) {
        marked[key]?.remove(reason)
        if marked[key]?.isEmpty == true { marked[key] = nil }
    }

    func setExpiry(_ date: CalendarDate?) {
        expiry = date
        expiryType = type
        expiryReasons = []
    }

    /// Seals the pages and the fields into the vault. False when it didn't: `saveError` says why, or
    /// `duplicate` holds what the vault already has.
    /// - Parameter onSaved: runs the moment the vault has the document, before anything else can, so a
    ///   lock right after never reports the saved scan as dropped.
    func save(onSaved: () -> Void = {}) async -> Bool {
        // One save at a time: a second tap while the first is being written would save a duplicate.
        guard !saving else { return false }
        saving = true
        // Simpan was answered; if this save fails, the next tap asks again, except about these pages.
        asking = false
        answeredPages = pageNotes
        defer { saving = false }
        var fields: [String: String] = [:]
        // A value that can't be stored is never saved; its field shows why.
        guard firstProblem() == nil else { return false }
        for key in fieldKeys {
            let text = Self.trimmed(values[key])
            guard !text.isEmpty else { continue }
            fields[key] = Self.dateKeys.contains(key) ? Self.yearFirst(text) : text
        }
        // Taken before the encode, which can take a moment: what's saved is what was shown at Simpan.
        let type = type
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let expiry = hasExpiry ? expiry : nil
        if let candidate = DuplicateCheck.candidate(type: type, values: fields), candidate != acceptedDuplicate {
            do {
                duplicate = try await DuplicateCheck.find(candidate, in: store)
                if duplicate != nil { return false }
            } catch {
                // Only a lock comes here; it drops the scan, as a locked save would.
                saveError = RecoveryMapping.screen(forSaveError: error)
                return false
            }
        }
        let encoded = await Self.encoded(pages, with: encode)
        // A page that can't be prepared is never left out, so nothing is saved.
        guard encoded.count == pages.count else {
            Logger.scan.error("A page couldn't be encoded; nothing was saved")
            saveError = .saveFailed
            return false
        }
        do {
            _ = try await store.createDocument(
                type: type, label: trimmedLabel.isEmpty ? nil : trimmedLabel, expiry: expiry,
                pinned: false, fields: DocumentFields(fields), pages: encoded)
            onSaved()
            return true
        } catch {
            // Only the kind of error; never a field or a path.
            Logger.scan.error("Save failed: \(ErrorSummary.describe(error), privacy: .public)")
            // A locked vault drops the scan anyway, and says so after unlocking.
            saveError = RecoveryMapping.screen(forSaveError: error)
            return false
        }
    }
}

extension ReviewModel {
    enum FieldProblem: Equatable {
        case notADate
        case birthDateInFuture
        case nikLength
    }

    /// The field lost focus, so typing is done: a filled one is judged now.
    func fieldLeft(_ key: String) {
        let text = Self.trimmed(values[key])
        guard !text.isEmpty else { return }
        problems[key] = Self.problem(with: text, for: key)
    }

    /// Judges every filled field, shows each one's reason, and returns the first wrong one in screen order.
    func firstProblem() -> String? {
        var first: String?
        for key in fieldKeys {
            let text = Self.trimmed(values[key])
            guard !text.isEmpty, let problem = Self.problem(with: text, for: key) else { continue }
            problems[key] = problem
            first = first ?? key
        }
        return first
    }

    /// What shows under a value. A refusal replaces a mark: it's what has to change before Simpan works.
    enum Note: Equatable {
        case refusal(FieldProblem)
        /// "Periksa lagi", with the first reason when one is known.
        case mark(CheckReason?)
        /// The expiry was read or picked for a kind of document whose date means something else.
        case dateFromAnotherType
    }

    func note(for key: String) -> Note? {
        if let problem = problems[key] { return .refusal(problem) }
        var reasons = marked[key] ?? []
        // These speak of the scanned document's number and layout, which another kind of document doesn't have.
        if Self.dateKind(type) != Self.dateKind(scannedType) {
            reasons.subtract([.disagreesWithBirthDate, .mixedLayout])
        }
        return reasons.min().map(Note.mark)
    }

    var typeNote: Note? { typeReasons.min().map(Note.mark) }

    var expiryNote: Note? {
        // What was said of the date belongs to the kind of document it was read or picked for.
        if Self.dateKind(type) != Self.dateKind(expiryType) {
            return expiry != nil ? .dateFromAnotherType : marksMissingExpiry ? .mark(nil) : nil
        }
        if let reason = expiryReasons.min() { return .mark(reason) }
        // Switched to a SIM by hand, nothing was read, so no reason is true.
        return marksMissingExpiry ? .mark(nil) : nil
    }

    /// "Cocok dengan tanggal lahir": only for a scan the parser confirmed, until either value is edited or
    /// gets a mark or a refusal. Two values the user typed say nothing about the card.
    var showsBirthDateMatch: Bool {
        guard birthDateConfirmed, Self.dateKind(type) == Self.dateKind(scannedType), let number = numberKey
        else { return false }
        return [number, FieldKey.birthDate].allSatisfy { !edited.contains($0) && note(for: $0) == nil }
    }

    /// The field whose digits hold the birth date: a KTP's NIK, or a SIM's number.
    var numberKey: String? { fieldKeys.first { $0 == FieldKey.nik || $0 == FieldKey.simNumber } }

    /// A KTP saved without its NIK is asked about first, never refused: an old photo can be blurred there.
    var nikMissing: Bool { fieldKeys.contains(FieldKey.nik) && Self.trimmed(values[FieldKey.nik]).isEmpty }

    /// What Simpan does next.
    enum SaveStep: Equatable {
        /// A wrong value; Simpan goes to its field.
        case refuse(String)
        case askNIK
        /// A page was read as another document.
        case askPages
        case save
    }

    /// Simpan was tapped: a wrong value is refused first, then an empty NIK and a page read as another
    /// document are asked about. Nil while an alert from an earlier tap is still being answered, so a quick
    /// second tap never stacks two.
    func saveStep() -> SaveStep? {
        guard !asking, duplicate == nil else { return nil }
        if let key = firstProblem() { return .refuse(key) }
        return ask(nikMissing ? .askNIK : stepAfterNIK)
    }

    /// "Simpan saja" in the empty NIK's alert.
    func saveStepWithoutNIK() -> SaveStep {
        ask(stepAfterNIK)
    }

    /// An alert from Simpan closed, or won't show, so the next tap asks again.
    func alertAnswered() {
        asking = false
    }

    /// Simpan in the duplicate alert.
    func acceptDuplicate() {
        acceptedDuplicate = duplicate?.candidate
        duplicate = nil
    }

    /// The duplicate alert closed, or couldn't show.
    func duplicateAnswered() {
        duplicate = nil
    }

    private var stepAfterNIK: SaveStep {
        pageNotes.saveWarning == nil || pageNotes == answeredPages ? .save : .askPages
    }

    private func ask(_ step: SaveStep) -> SaveStep {
        asking = step != .save
        return step
    }

    private static func trimmed(_ text: String?) -> String {
        text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// What a document's date means: every SIM class shares one meaning, an STNK's is its tax.
    private static func dateKind(_ type: DocumentType) -> String {
        type.isSIM ? "sim" : type.rawValue
    }

    /// Why a value can't be stored, or nil when it can. Only a NIK's length and dates are judged.
    static func problem(with text: String, for key: String) -> FieldProblem? {
        if key == FieldKey.nik {
            return NIK.isWellFormed(text) ? nil : .nikLength
        }
        guard dateKeys.contains(key) else { return nil }
        guard let date = yearFirst(text).flatMap(CalendarDate.init) else { return .notADate }
        return key == FieldKey.birthDate && date > .today ? .birthDateInFuture : nil
    }

    /// Off the main actor: a few full-size pages take long enough to freeze the screen.
    @concurrent
    private static func encoded(_ pages: [CGImage], with encode: @Sendable (CGImage) -> Data?) async -> [Data] {
        pages.compactMap(encode)
    }
}
