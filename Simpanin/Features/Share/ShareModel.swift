//
//  ShareModel.swift
//  Simpanin
//
//  Created by Inez Amanda on 4/11/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import CoreGraphics
import Foundation
import OSLog
import Observation
import VaultCore

/// Shows the share sheet with files. `onClose` comes once, with whether a target took them; a sheet a lock
/// takes away may never call it.
@MainActor protocol SharePresenting: AnyObject {
    /// False when there's nowhere to show it from.
    func present(_ files: [URL], onClose: @escaping @MainActor (_ taken: Bool) -> Void) -> Bool
}

/// Bagikan salinan: a purpose, a preview of page 1 with the mark, then every page marked and handed to the
/// share sheet as files. Pages are read through `PageReading` only, so nothing here can change the document.
@MainActor @Observable
final class ShareModel {
    enum Preview {
        case loading
        case shown(CGImage)
        case failed
    }

    enum Phase: Equatable {
        case editing
        case preparing(page: Int, count: Int)
        case shareSheetUp
        /// Shared, or the document has gone: the sheet closes.
        case closed
    }

    enum Problem: Equatable {
        /// A page couldn't be opened, so nothing was shared.
        case pageUnavailable
        case storageFull
        /// The copies couldn't be made for another reason.
        case notMade
    }

    /// The preview's page is decoded to this size, the document screen's pager size.
    nonisolated static let previewPixelSize = 1_200
    /// A shared page is at most this size on its longer side, like the viewer's.
    nonisolated static let sharedPixelSize = 3_000

    let document: Document
    var purpose = ""
    private(set) var preview = Preview.loading
    /// Page 1 with the mark as it will be shared, redrawn as the purpose changes.
    private(set) var markedPreview: CGImage?
    private(set) var phase = Phase.editing
    var problem: Problem?
    /// The day the preview shows; a share reads the clock again when Bagikan is tapped.
    private(set) var day: Date

    private let pageReader: any PageReading
    private let copies: SharedCopies
    private let presenter: any SharePresenting
    private let clock: any VaultClock
    private let timeZone: TimeZone
    private let onShareSheetShown: () -> Void
    private let onShareSheetEnded: () -> Void
    /// Page 1 as read, kept while the sheet is open so the mark can be redrawn as the purpose changes.
    private var previewPage: CGImage?
    /// The copies of the share in hand; nil once they're deleted.
    private var folder: URL?

    init(
        document: Document, pageReader: any PageReading, copies: SharedCopies, presenter: any SharePresenting,
        clock: any VaultClock = SystemClock(), timeZone: TimeZone = .current,
        onShareSheetShown: @escaping () -> Void = {}, onShareSheetEnded: @escaping () -> Void = {}
    ) {
        self.document = document
        self.pageReader = pageReader
        self.copies = copies
        self.presenter = presenter
        self.clock = clock
        self.timeZone = timeZone
        self.onShareSheetShown = onShareSheetShown
        self.onShareSheetEnded = onShareSheetEnded
        day = clock.now
    }

    var pageCount: Int { document.pageIDs.count }
    var mark: String { SharePurpose.mark(purpose: purpose, date: day, timeZone: timeZone) }
    var canShare: Bool {
        guard case .failed = preview else { return SharePurpose.canShare(purpose) && !isPreparing }
        return false
    }

    private var isPreparing: Bool {
        if case .preparing = phase { true } else { false }
    }

    func loadPreview() async {
        guard let pageID = document.pageIDs.first else {
            preview = .failed
            return
        }
        let data: Data
        do {
            data = try await pageReader.pageData(pageID, of: document.id)
        } catch {
            Logger.share.error("Preview not opened: \(ErrorSummary.describe(error), privacy: .public)")
            preview = .failed
            return
        }
        guard let page = await CGImage.reduced(from: data, to: Self.previewPixelSize) else {
            Logger.share.error("Preview not decoded")
            preview = .failed
            return
        }
        previewPage = page
        preview = .shown(page)
        await redrawPreview()
    }

    func redrawPreview() async {
        guard let previewPage else { return }
        let text = mark
        let marked = await Self.marked(previewPage, text: text)
        // A draw for older text can finish after a newer one; the preview always matches the field.
        guard !Task.isCancelled, text == mark else { return }
        markedPreview = marked
    }

    /// After midnight, or a change of time zone or clock.
    func refreshDay() {
        day = clock.now
    }

    func share() async {
        guard canShare else { return }
        // A sheet that closed without telling is over too, so a lock now isn't told as a stopped share.
        if phase == .shareSheetUp { onShareSheetEnded() }
        removeCopies()
        problem = nil
        day = clock.now
        let text = mark
        let pageIDs = document.pageIDs
        phase = .preparing(page: 1, count: pageIDs.count)
        var made: URL?
        do {
            let folder = try copies.makeFolder()
            made = folder
            self.folder = folder
            var files: [URL] = []
            for (index, pageID) in pageIDs.enumerated() {
                phase = .preparing(page: index + 1, count: pageIDs.count)
                let data = try await pageReader.pageData(pageID, of: document.id)
                try Task.checkCancellation()
                let name = SharedCopies.fileName(page: index + 1, date: day, timeZone: timeZone)
                files.append(try await Self.markedCopy(of: data, text: text, named: name, in: folder, copies: copies))
                try Task.checkCancellation()
            }
            // Left while the last page was being written: a lock or Batal.
            guard self.folder == folder else { throw CancellationError() }
            guard presenter.present(files, onClose: { [weak self] taken in self?.closed(folder, taken: taken) })
            else { throw ShareError.nowhereToShow }
            phase = .shareSheetUp
            onShareSheetShown()
        } catch {
            removeCopies()
            // The screen may have gone while a page was still being written; this runs after the write.
            if let made { remove(made) }
            // A sheet that has gone shows nothing.
            guard phase != .closed else { return }
            phase = .editing
            problem = Self.problem(for: error)
        }
    }

    /// The sheet is gone, by Batal, a closed document or a lock: its copies go with it.
    func screenLeft() {
        removeCopies()
        if phase == .shareSheetUp { onShareSheetEnded() }
        phase = .closed
    }

    private func closed(_ folder: URL, taken: Bool) {
        // A sheet the lock took away can still report later; its copies are gone by then.
        guard self.folder == folder, phase == .shareSheetUp else { return }
        removeCopies()
        do {
            try copies.clearShareSheetCopies()
        } catch {
            Logger.share.error("Share sheet copies weren't removed: \(ErrorSummary.describe(error), privacy: .public)")
        }
        onShareSheetEnded()
        phase = taken ? .closed : .editing
    }

    private func removeCopies() {
        guard let folder else { return }
        self.folder = nil
        remove(folder)
    }

    private func remove(_ folder: URL) {
        do {
            try copies.remove(folder)
        } catch {
            // Launch and the lock clear the folder again.
            Logger.share.error("Removing a share failed: \(ErrorSummary.describe(error), privacy: .public)")
        }
    }

    private static func problem(for error: any Error) -> Problem? {
        if VaultStore.isOutOfSpace(error) { return .storageFull }
        return switch error {
        case is CancellationError, VaultError.locked: nil
        case VaultError.storageFull: .storageFull
        case ShareError.pageUnreadable, VaultError.pageNotFound, VaultError.authenticationFailed: .pageUnavailable
        default: .notMade
        }
    }

    private enum ShareError: Error {
        case pageUnreadable, nowhereToShow
    }

    @concurrent private static func marked(_ page: CGImage, text: String) async -> CGImage? {
        WatermarkRenderer.marked(page, text: text)
    }

    /// One page at a time: decoded, marked and written, then let go before the next is read.
    @concurrent private static func markedCopy(
        of data: Data, text: String, named name: String, in folder: URL, copies: SharedCopies
    ) async throws -> URL {
        guard let page = await CGImage.reduced(from: data, to: sharedPixelSize),
            let marked = WatermarkRenderer.marked(page, text: text)
        else { throw ShareError.pageUnreadable }
        return try copies.write(marked, named: name, in: folder)
    }
}
