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
import ImageIO
import OSLog
import Observation
import Parsers
import UniformTypeIdentifiers
import VaultCore

/// "Periksa data": what a scan read, for the user to check and correct before it's saved. Everything
/// stays in memory until "Simpan ke vault".
@MainActor @Observable
final class ReviewModel {
    private(set) var pages: [CGImage] = []
    var type = DocumentType.other
    var label = ""
    /// The text of each field, by `FieldKey`, as read or as typed.
    private(set) var values: [String: String] = [:]
    /// Fields marked "Periksa lagi".
    private(set) var marked: Set<String> = []
    private(set) var typeNeedsCheck = false
    private(set) var expiry: CalendarDate?
    private(set) var expiryNeedsCheck = false
    var saveError: RecoveryScreen?
    private(set) var saving = false
    /// What the scan read, to tell what the user typed over.
    private var scanned: [String: String] = [:]

    private let store: any DocumentStoring
    private let encode: @Sendable (CGImage) -> Data?

    init(store: any DocumentStoring, encode: @escaping @Sendable (CGImage) -> Data? = PageEncoding.jpeg) {
        self.store = store
        self.encode = encode
    }

    /// The fields the chosen type has, in the order the screen shows them.
    var fieldKeys: [String] {
        if type == .ktp { return [FieldKey.nik, FieldKey.name, FieldKey.birthDate] }
        if type.isSIM { return [FieldKey.simNumber, FieldKey.name, FieldKey.birthDate] }
        return []
    }

    /// Only a SIM has an expiry to show and edit here; a KTP is valid for life.
    var hasExpiry: Bool { type.isSIM }

    /// The type has an expiry and none was read or picked: shown as "Belum diisi", marked, never as today.
    var expiryMissing: Bool { hasExpiry && expiry == nil }

    /// A label shows in the list without opening the document, so it must not hold a number.
    var labelLooksLikeANumber: Bool { label.filter(\.isNumber).count >= 8 }

    /// The user typed over something the scan read; a new scan would replace it.
    var hasTypedChanges: Bool { values != scanned }

    /// After a scan or a rescan: every field comes from the new pages. The label stays.
    func load(_ result: ParsedDocument?, pages: [CGImage]) {
        self.pages = pages
        type = result?.type ?? .other
        values = (result?.fields.values ?? [:]).reduce(into: [:]) { shown, field in
            shown[field.key] = Self.dateKeys.contains(field.key) ? Self.dayFirst(field.value) : field.value
        }
        scanned = values
        marked = result?.needsCheck ?? []
        typeNeedsCheck = result?.typeNeedsCheck ?? true
        expiry = result?.expiry
        expiryNeedsCheck = result?.expiryNeedsCheck ?? false
        saveError = nil
    }

    func setValue(_ text: String, for key: String) {
        values[key] = text
        // The user looked at it and decided, so it's no longer the parser's guess.
        marked.remove(key)
    }

    func setExpiry(_ date: CalendarDate?) {
        expiry = date
        expiryNeedsCheck = false
    }

    /// Seals the pages and the fields into the vault. False when it didn't; `saveError` says why.
    /// - Parameter onSaved: runs the moment the vault has the document, before anything else can, so a
    ///   lock right after never reports the saved scan as dropped.
    func save(onSaved: () -> Void = {}) async -> Bool {
        // One save at a time: a second tap while the first is being written would save a duplicate.
        guard !saving else { return false }
        saving = true
        defer { saving = false }
        var fields: [String: String] = [:]
        for key in fieldKeys {
            let text = values[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !text.isEmpty else { continue }
            if Self.dateKeys.contains(key) {
                // A date that can't exist is never stored; the field is marked for the user to fix.
                guard let date = Self.yearFirst(text) else {
                    marked.insert(key)
                    return false
                }
                fields[key] = date
            } else {
                fields[key] = text
            }
        }
        let encoded = pages.compactMap(encode)
        // A page that can't be prepared is never left out, so nothing is saved.
        guard encoded.count == pages.count else {
            Logger.scan.error("A page couldn't be encoded; nothing was saved")
            saveError = .saveFailed
            return false
        }
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            _ = try await store.createDocument(
                type: type, label: trimmedLabel.isEmpty ? nil : trimmedLabel, expiry: hasExpiry ? expiry : nil,
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
    /// Fields holding a date: shown day first, as on the card, and stored as YYYY-MM-DD like every date
    /// in the vault.
    static let dateKeys: Set<String> = [FieldKey.birthDate]

    static func dayFirst(_ stored: String) -> String {
        guard let date = CalendarDate(stored) else { return stored }
        return String(format: "%02d-%02d-%04d", date.day, date.month, date.year)
    }

    /// "17-08-1990", also with dots, slashes or spaces between; nil when the date can't exist.
    static func yearFirst(_ typed: String) -> String? {
        guard let match = typed.wholeMatch(of: /\s*([0-9]{1,2})[-.\/ ]([0-9]{1,2})[-.\/ ]([0-9]{4})\s*/),
            let day = Int(match.1), let month = Int(match.2), let year = Int(match.3)
        else { return nil }
        return CalendarDate(year: year, month: month, day: day)?.string
    }
}

/// Turns a page into the bytes that are sealed in the vault.
nonisolated enum PageEncoding {
    /// JPEG, like VisionKit's own pages, at a quality that keeps small print readable.
    static func jpeg(_ page: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, page, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}
