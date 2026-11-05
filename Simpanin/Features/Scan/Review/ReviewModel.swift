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
    /// The pages made small once after the scan, for the strip, so it never draws a full-size scan.
    private(set) var thumbnails: [PageThumbnail] = []
    /// The fields as read and corrected, with their marks and refusals.
    private(set) var form = DocumentForm()
    /// Set by the type sheet; picking one is the user's decision, so the parser's doubt goes.
    var type: DocumentType {
        get { form.type }
        set {
            form.type = newValue
            typeReasons = []
        }
    }
    var label = ""
    var values: [String: String] { form.values }
    var marked: [String: Set<CheckReason>] { form.marked }
    var problems: [String: DocumentForm.FieldProblem] { form.problems }
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
    var saveError: RecoveryScreen?
    private(set) var saving = false
    /// An alert from Simpan is up, or about to follow another.
    private var asking = false
    /// Found by the check on Simpan; Simpan asks nothing until its alert is answered.
    private(set) var duplicate: DuplicateCheck.Found?
    /// A save is being written, or its duplicate alert is about to open: nothing may drop or replace the scan.
    var saveInProgress: Bool { saving || duplicate != nil }
    /// Simpan in the duplicate alert, kept while the number and type stay the same, also after a failed save.
    private var acceptedDuplicate: DuplicateCheck.Candidate?
    /// What the pages alert said when it was answered; while the notes say the same, it isn't asked again.
    private var answeredPages: PageNotes?
    /// The expiry the scan read; the fields and type it read are the form's `original` and `loadedType`.
    private var scannedExpiry: CalendarDate?

    private let store: any DocumentStoring
    private let encode: @Sendable (CGImage) -> Data?
    private let storePhotos: @Sendable ([Data]) async -> [Data]?
    private var savedPages = SavedPages.shownPages

    init(
        store: any DocumentStoring, encode: @escaping @Sendable (CGImage) -> Data? = PageEncoding.jpeg,
        storePhotos: @escaping @Sendable ([Data]) async -> [Data]? = PhotoDecoding.storedPages
    ) {
        self.store = store
        self.encode = encode
        self.storePhotos = storePhotos
    }

    /// Worked out each time from the reading and the type chosen now, never stored.
    var pageNotes: PageNotes { PageNotes(reading: reading, pageCount: pages.count, chosen: type) }

    var fieldKeys: [String] { form.fieldKeys }

    /// SIM, Paspor and STNK have a printed expiry to show and edit here; a KTP is valid for life.
    var hasExpiry: Bool { ExpiryText.hasPrintedExpiry(type) }

    /// The type has an expiry and none was read or picked: shown as "Belum diisi", marked, never as today.
    var expiryMissing: Bool { hasExpiry && expiry == nil }

    /// Only a SIM's parser should have read the date; Paspor and STNK have none yet, so an empty date there
    /// isn't a misread and gets no "Periksa lagi".
    var marksMissingExpiry: Bool { expiryMissing && type.isSIM }

    /// The user changed something the scan read, a field, the type or the expiry; a new scan would
    /// replace it.
    var hasUserChanges: Bool { values != form.original || type != form.loadedType || expiry != scannedExpiry }

    /// After a scan or a rescan: every field comes from the new pages. The label stays. The pages and where
    /// their saved copies come from are set together, so a new pick never saves the old photos.
    func load(
        _ result: ParsedDocument?, pages: [CGImage], thumbnails: [PageThumbnail], reading: ScanReading? = nil,
        saving savedPages: SavedPages = .shownPages
    ) {
        self.pages = pages
        self.savedPages = savedPages
        self.thumbnails = thumbnails
        // Always replaced, so a rescan that failed never keeps the old scan's notes.
        self.reading = reading
        // An alert that was about to follow Simpan saja belongs to the old pages, as do the answers.
        asking = false
        duplicate = nil
        acceptedDuplicate = nil
        answeredPages = nil
        let values = (result?.fields.values ?? [:]).reduce(into: [:]) { shown, field in
            shown[field.key] =
                FieldDates.dateKeys.contains(field.key) ? DocumentFieldStyle.dayFirst(field.value) : field.value
        }
        form = DocumentForm(type: result?.type ?? .other, values: values, marked: result?.reasons ?? [:])
        scannedExpiry = result?.expiry
        typeReasons = result?.typeReasons ?? [.noDocumentRecognized]
        expiry = result?.expiry
        expiryType = type
        expiryReasons = result?.expiryReasons ?? []
        birthDateConfirmed = result?.birthDateConfirmed ?? false
        edited = []
        // A wrong value the scan read shows its reason at once, not only when Simpan is tapped.
        _ = firstProblem()
        saveError = nil
    }

    func setValue(_ text: String, for key: String) {
        guard form.setValue(text, for: key) else { return }
        edited.insert(key)
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
        // A value that can't be stored is never saved; its field shows why.
        guard firstProblem() == nil else { return false }
        let fields = form.savedFields()
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
        let encoded = await savedPages.encoded(pages, encode: encode, storePhotos: storePhotos)
        // Locking the vault removes this screen and cancels its save; a vault opened again meanwhile mustn't
        // get the document the notice calls dropped.
        guard !Task.isCancelled else { return false }
        // A page that can't be prepared is never left out, so nothing is saved.
        guard let encoded else {
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
    func fieldLeft(_ key: String) { form.fieldLeft(key) }

    func firstProblem() -> String? { form.firstProblem() }

    func note(for key: String) -> DocumentForm.Note? { form.note(for: key) }

    var typeNote: DocumentForm.Note? { typeReasons.min().map(DocumentForm.Note.mark) }

    var expiryNote: DocumentForm.Note? {
        // What was said of the date belongs to the kind of document it was read or picked for.
        if DocumentForm.dateKind(type) != DocumentForm.dateKind(expiryType) {
            return expiry != nil ? .dateFromAnotherType : marksMissingExpiry ? .mark(nil) : nil
        }
        if let reason = expiryReasons.min() { return .mark(reason) }
        // Switched to a SIM by hand, nothing was read, so no reason is true.
        return marksMissingExpiry ? .mark(nil) : nil
    }

    /// "Cocok dengan tanggal lahir": only for a scan the parser confirmed, until either value is edited or
    /// gets a mark or a refusal. Two values the user typed say nothing about the card.
    var showsBirthDateMatch: Bool {
        guard birthDateConfirmed, DocumentForm.dateKind(type) == DocumentForm.dateKind(form.loadedType),
            let number = numberKey
        else { return false }
        return [number, FieldKey.birthDate].allSatisfy { !edited.contains($0) && note(for: $0) == nil }
    }

    var numberKey: String? { form.numberKey }

    var nikMissing: Bool { form.nikMissing }

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
}
