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
    var expiry: CalendarDate?
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

    /// A label shows in the list without opening the document, so it must not hold a number.
    var labelLooksLikeANumber: Bool { label.filter(\.isNumber).count >= 8 }

    /// The user typed over something the scan read; a new scan would replace it.
    var hasTypedChanges: Bool { values != scanned }

    /// After a scan or a rescan: every field comes from the new pages. The label stays.
    func load(_ result: ParsedDocument?, pages: [CGImage]) {
        self.pages = pages
        type = result?.type ?? .other
        values = result?.fields.values ?? [:]
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

    /// Seals the pages and the fields into the vault. False when it didn't; `saveError` says why.
    func save() async -> Bool {
        saving = true
        defer { saving = false }
        let encoded = pages.compactMap(encode)
        // A page that can't be prepared is never left out, so nothing is saved.
        guard encoded.count == pages.count else {
            Logger.scan.error("A page couldn't be encoded; nothing was saved")
            saveError = .saveFailed
            return false
        }
        var fields: [String: String] = [:]
        for key in fieldKeys {
            let text = values[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !text.isEmpty { fields[key] = text }
        }
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            _ = try await store.createDocument(
                type: type, label: trimmedLabel.isEmpty ? nil : trimmedLabel, expiry: hasExpiry ? expiry : nil,
                pinned: false, fields: DocumentFields(fields), pages: encoded)
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
