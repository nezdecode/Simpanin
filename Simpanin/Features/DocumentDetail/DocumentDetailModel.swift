//
//  DocumentDetailModel.swift
//  Simpanin
//
//  Created by Inez Amanda on 28/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import CoreGraphics
import Foundation
import ImageIO
import Observation
import VaultCore
import os

/// One saved document, opened. Its fields and reduced pages are decrypted only while the screen is up,
/// and go with the model when the screen closes or the vault locks.
@MainActor @Observable
final class DocumentDetailModel {
    enum Phase: Equatable {
        case loading
        case loaded
        /// The fields couldn't be opened; Coba lagi tries again.
        case failed
        /// The document is no longer there, so the screen goes back to the list.
        case gone
    }

    enum PageState {
        case loading
        case shown(CGImage)
        case failed
    }

    struct Field: Identifiable {
        let key: String
        let title: LocalizedStringResource
        /// Nil when nothing is stored; the row says so with `empty`.
        let value: String?
        let isNumber: Bool

        var id: String { key }
        /// "Belum diisi" under the title, as under Berlaku.
        var empty: LocalizedStringResource { "review.expiryMissing" }
        /// A copied date rarely pastes into a form, so the birth date has no copy button.
        var canCopy: Bool { value != nil && key != FieldKey.birthDate }

        var copyLabel: LocalizedStringResource {
            switch key {
            case FieldKey.nik: "detail.copyNIK"
            case FieldKey.simNumber: "detail.copySIMNumber"
            default: "detail.copyName"
            }
        }

        /// The toast's title; it never holds the value.
        var copiedTitle: LocalizedStringResource {
            switch key {
            case FieldKey.nik: "detail.nikCopied"
            case FieldKey.simNumber: "detail.simNumberCopied"
            default: "detail.nameCopied"
            }
        }

        func revealLabel(numberShown: Bool) -> LocalizedStringResource {
            switch (key, numberShown) {
            case (FieldKey.simNumber, false): "detail.showSIMNumber"
            case (FieldKey.simNumber, true): "detail.hideSIMNumber"
            case (_, false): "detail.showNIK"
            case (_, true): "detail.hideNIK"
            }
        }
    }

    /// Pages in the pager are reduced to this many pixels on their longer side; only the viewer decodes
    /// one at full size.
    nonisolated static let reducedPixelSize = 1_200

    let document: Document
    private(set) var phase = Phase.loading
    private(set) var pages: [PageState] = []
    private(set) var numberShown = false
    var toast: Toast?
    /// Hapus worked, so the screen closes.
    private(set) var closed = false

    private let store: any DocumentStoring
    private let pageReader: any PageReading
    private let clipboard: any Clipboard
    private let onDelete: (DocumentID) async -> Bool
    /// Decrypted while the screen is up; never cached or kept elsewhere.
    private var fields: DocumentFields?

    init(
        document: Document, store: any DocumentStoring, pageReader: any PageReading, clipboard: any Clipboard,
        onDelete: @escaping (DocumentID) async -> Bool
    ) {
        self.document = document
        self.store = store
        self.pageReader = pageReader
        self.clipboard = clipboard
        self.onDelete = onDelete
    }

    var hasPages: Bool { !document.pageIDs.isEmpty }

    /// The type's own fields, in its order; any other key stored is never shown.
    var rows: [Field] {
        DocumentFieldStyle.keys(for: document.type).map { key in
            let stored = fields?.values[key].flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
            let isNumber = key == FieldKey.nik || key == FieldKey.simNumber
            let value: String? =
                if isNumber {
                    stored.map(DocumentNumber.init).flatMap { number in
                        number.isEmpty ? nil : (numberShown ? number.shown : number.masked)
                    }
                } else if key == FieldKey.birthDate {
                    stored.map(DocumentFieldStyle.dayFirst)
                } else {
                    stored
                }
            return Field(
                key: key, title: DocumentFieldStyle.title(for: key), value: value,
                isNumber: isNumber)
        }
    }

    /// The fields first, then each page on its own. The fields are read once, again only after a failure
    /// (Coba lagi). Leaving the screen stops the page reads; coming back reads only the pages still missing.
    func load() async {
        switch phase {
        case .gone: return
        case .loaded: break
        case .loading, .failed:
            guard await loadFields() else { return }
            pages = document.pageIDs.map { _ in .loading }
        }
        for (index, pageID) in document.pageIDs.enumerated() {
            guard case .loading = pages[index] else { continue }
            guard !Task.isCancelled else { return }
            do {
                let data = try await pageReader.pageData(pageID, of: document.id)
                // Not kept after the screen has gone; a return reads it again.
                guard !Task.isCancelled else { return }
                pages[index] = await Self.reduced(data).map(PageState.shown) ?? .failed
            } catch VaultError.locked {
                return
            } catch {
                Logger.library.error("Page not opened: \(ErrorSummary.describe(error), privacy: .public)")
                pages[index] = .failed
            }
        }
    }

    private func loadFields() async -> Bool {
        phase = .loading
        do {
            fields = try await store.fields(of: document.id)
            phase = .loaded
            return true
        } catch VaultError.locked {
            // The lock takes this screen away; there's nothing to say.
        } catch VaultError.documentNotFound {
            phase = .gone
        } catch {
            Logger.library.error("Document not opened: \(ErrorSummary.describe(error), privacy: .public)")
            phase = .failed
        }
        return false
    }

    /// A page at full size, for the viewer only, read again each time; the model doesn't keep it.
    func fullPage(_ index: Int) async -> CGImage? {
        guard document.pageIDs.indices.contains(index) else { return nil }
        do {
            return await Self.decoded(try await pageReader.pageData(document.pageIDs[index], of: document.id))
        } catch {
            Logger.library.error("Page not opened: \(ErrorSummary.describe(error), privacy: .public)")
            return nil
        }
    }

    func toggleNumber() { numberShown.toggle() }

    func screenLeft() { numberShown = false }

    func appLeftForeground() { numberShown = false }

    /// The viewer covers the screen, so the number shouldn't be left showing behind it.
    func viewerOpened() { numberShown = false }

    /// The number as digits only, the name as stored. Copying never shows the number.
    func copy(_ key: String) {
        guard let row = rows.first(where: { $0.key == key }), row.canCopy, let stored = fields?.values[key] else {
            return
        }
        clipboard.copy(row.isNumber ? DocumentNumber(stored).copied : stored)
        toast = Toast(title: row.copiedTitle, detail: "detail.copiedExpires")
    }

    func delete() async {
        if await onDelete(document.id) { closed = true }
    }

    /// ImageIO's thumbnail, off the main actor; never `UIImage(data:)`, which decodes the full bitmap.
    @concurrent private static func reduced(_ data: Data) async -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: reducedPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    @concurrent private static func decoded(_ data: Data) async -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [kCGImageSourceShouldCacheImmediately: true]
        return CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary)
    }
}
