//
//  EditDocumentModel.swift
//  Simpanin
//
//  Created by Inez Amanda on 5/11/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import OSLog
import Observation
import VaultCore

/// Edit dokumen: a saved document's label, fields and expiry. Its type and pages stay as they are.
@MainActor @Observable
final class EditDocumentModel {
    enum SaveStep: Equatable {
        /// A changed value is wrong; Simpan goes to its field.
        case refuse(String)
        case askNIK
        case save
    }

    let document: Document
    private(set) var form: DocumentForm
    var label: String
    private(set) var expiry: CalendarDate?
    var saveError: RecoveryScreen?
    private(set) var saving = false
    /// Found by the check on Simpan; Simpan asks nothing until its alert is answered.
    private(set) var duplicate: DuplicateCheck.Found?
    /// Simpan in the duplicate alert, kept while the number stays the same.
    private var acceptedDuplicate: DuplicateCheck.Candidate?
    /// An alert from Simpan is up, or about to follow another.
    private var asking = false

    private let store: any DocumentStoring

    /// - Parameter fields: the fields the document screen already opened, so nothing is decrypted again.
    init(document: Document, fields: DocumentFields, store: any DocumentStoring) {
        self.document = document
        form = DocumentForm(type: document.type, stored: fields)
        label = document.label ?? ""
        expiry = document.expiry
        self.store = store
    }

    /// SIM, Paspor and STNK have a printed expiry to edit. On any other type a stored date is kept as it is.
    var hasExpiry: Bool { ExpiryText.hasPrintedExpiry(document.type) }

    var hasChanges: Bool {
        !form.changedKeys.isEmpty || label != (document.label ?? "") || expiry != document.expiry
    }

    func setValue(_ text: String, for key: String) { form.setValue(text, for: key) }

    func fieldLeft(_ key: String) { form.fieldLeft(key) }

    func setExpiry(_ date: CalendarDate?) {
        guard hasExpiry else { return }
        expiry = date
    }

    /// Simpan was tapped: a changed wrong value is refused first, then an emptied NIK is asked about. Nil
    /// while an alert from an earlier tap is still being answered.
    func saveStep() -> SaveStep? {
        guard !asking, duplicate == nil else { return nil }
        if let key = form.firstProblem(among: form.changedKeys) { return .refuse(key) }
        return ask(form.nikEmptied ? .askNIK : .save)
    }

    /// "Simpan saja" in the empty NIK's alert.
    func saveStepWithoutNIK() -> SaveStep { ask(.save) }

    /// An alert from Simpan closed, or won't show, so the next tap asks again.
    func alertAnswered() { asking = false }

    /// Simpan in the duplicate alert.
    func acceptDuplicate() {
        acceptedDuplicate = duplicate?.candidate
        duplicate = nil
    }

    /// The duplicate alert closed, or couldn't show.
    func duplicateAnswered() { duplicate = nil }

    private func ask(_ step: SaveStep) -> SaveStep {
        asking = step != .save
        return step
    }

    /// Writes the edit. False when it didn't: `saveError` says why, or `duplicate` holds what the vault already
    /// has.
    /// - Parameter onSaved: runs the moment the vault has the edit, before anything else can, so a lock right
    ///   after never reports it as dropped.
    func save(onSaved: () -> Void = {}) async -> Bool {
        // One save at a time, and only of a real change.
        guard !saving, hasChanges else { return false }
        saving = true
        asking = false
        defer { saving = false }
        guard form.firstProblem(among: form.changedKeys) == nil else { return false }
        let fields = form.savedFields()
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        // Only a number this edit changed is checked: an unchanged one was saved, and warned about, before.
        let candidate = DuplicateCheck.candidate(type: document.type, values: fields)
        let storedCandidate = DuplicateCheck.candidate(type: document.type, values: form.stored ?? [:])
        if let candidate, candidate != storedCandidate, candidate != acceptedDuplicate {
            do {
                duplicate = try await DuplicateCheck.find(candidate, in: store, excluding: document.id)
                if duplicate != nil { return false }
            } catch {
                // Only a lock comes here; it takes the screen away.
                saveError = RecoveryMapping.screen(forSaveError: error)
                return false
            }
        }
        // Locking the vault removes this screen and cancels its save; nothing is written after that.
        guard !Task.isCancelled else { return false }
        do {
            try await store.editDocument(
                document.id, type: document.type, label: trimmedLabel.isEmpty ? nil : trimmedLabel,
                expiry: expiry, pinned: document.pinned, fields: DocumentFields(fields))
            onSaved()
            return true
        } catch {
            // Only the kind of error; never a field or a path.
            Logger.library.error("Edit not saved: \(ErrorSummary.describe(error), privacy: .public)")
            saveError = RecoveryMapping.screen(forSaveError: error)
            return false
        }
    }
}
