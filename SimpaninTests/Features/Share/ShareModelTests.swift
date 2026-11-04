//
//  ShareModelTests.swift
//  SimpaninTests
//
//  Created by Inez Amanda on 4/11/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import ImageIO
import Testing
import UIKit
import VaultCore

@testable import Simpanin

/// Keeps what it was given instead of showing the share sheet, and closes only when the test says.
final class FakePresenter: SharePresenting {
    private(set) var presented: [[URL]] = []
    /// Whether every file existed when it was handed over.
    private(set) var filesExisted: [Bool] = []
    private var onClose: (@MainActor (Bool) -> Void)?
    var canPresent = true

    func present(_ files: [URL], onClose: @escaping @MainActor (Bool) -> Void) -> Bool {
        guard canPresent else { return false }
        presented.append(files)
        filesExisted.append(files.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
        self.onClose = onClose
        return true
    }

    func close(taken: Bool) { onClose?(taken) }
}

@MainActor
@Suite("Share model")
struct ShareModelTests {
    let store = FakeDocuments()
    let presenter = FakePresenter()
    let clock = FixedClock()
    let temporary: URL
    let utc = TimeZone(identifier: "UTC") ?? .gmt

    init() throws {
        temporary = FileManager.default.temporaryDirectory.appending(path: "share-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
    }

    static func page(width: Int = 1_600, height: Int = 1_000, gray: CGFloat = 1) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).pngData {
            UIColor(white: gray, alpha: 1).setFill()
            $0.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    final class Counts {
        var shown = 0
        var ended = 0
    }

    func model(
        pages: [Data] = [page(), page()], writeFile: @escaping SharedCopies.Write = SharedCopies.writeComplete,
        protector: any FileProtector = RecordingProtector(), counts: Counts = Counts()
    ) async throws -> ShareModel {
        let id = try await store.createDocument(
            type: .ktp, label: nil, expiry: nil, pinned: false, fields: DocumentFields([:]), pages: pages)
        let document = try #require(await store.documents().first { $0.id == id })
        let copies = SharedCopies(temporary: temporary, protector: protector, writeFile: writeFile)
        let share = ShareModel(
            document: document, pageReader: store, copies: copies, presenter: presenter, clock: clock, timeZone: utc,
            onShareSheetShown: { counts.shown += 1 }, onShareSheetEnded: { counts.ended += 1 })
        share.purpose = "Sewa kos"
        return share
    }

    /// Every file still in SharedCopies.
    func leftFiles() -> [String] {
        let root = temporary.appending(path: SharedCopies.folderName)
        let enumerator = FileManager.default.enumerator(atPath: root.path)
        return (enumerator?.allObjects as? [String] ?? []).filter { $0.hasSuffix(".jpg") }
    }

    func size(of url: URL) throws -> CGSize {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        return CGSize(width: image.width, height: image.height)
    }

    // MARK: - The date and the preview

    @Test func theDateIsReadWhenBagikanIsTapped() async throws {
        let share = try await model()
        clock.advance(by: 86_400)
        await share.share()
        let files = try #require(presenter.presented.first)
        let tomorrow = clock.now.formatted(.indonesianDate(timeZone: utc))
        #expect(files.allSatisfy { $0.lastPathComponent.contains(tomorrow) })
        #expect(share.mark == "Sewa kos · \(tomorrow)")
    }

    @Test func thePreviewShowsTheNewDayAfterMidnight() async throws {
        let share = try await model()
        let today = share.mark
        clock.advance(by: 86_400)
        share.refreshDay()
        #expect(share.mark != today)
        #expect(share.mark == "Sewa kos · \(clock.now.formatted(.indonesianDate(timeZone: utc)))")
    }

    @Test func thePreviewWaitsForPageOneAndShowsItsFailure() async throws {
        let share = try await model()
        await store.gateNextPageRead()
        let loading = Task { await share.loadPreview() }
        #expect(await store.waitUntilReadingPage())
        guard case .loading = share.preview else {
            Issue.record("not loading: \(share.preview)")
            return
        }
        await store.releasePageRead()
        await loading.value
        guard case .shown(let image) = share.preview else {
            Issue.record("not shown")
            return
        }
        #expect(max(image.width, image.height) <= ShareModel.previewPixelSize)
        #expect(share.markedPreview != nil)

        let broken = try await model()
        try await store.setUnreadablePage(#require(broken.document.pageIDs.first))
        await broken.loadPreview()
        guard case .failed = broken.preview else {
            Issue.record("not failed: \(broken.preview)")
            return
        }
        #expect(broken.markedPreview == nil)
        // Page 1 can't be shared either, so Bagikan says so at once instead of after a tap.
        #expect(!broken.canShare)
    }

    // MARK: - Pages and copies

    @Test func aCopyIsAtMost3000Pixels() async throws {
        let share = try await model(pages: [Self.page(width: 6_000, height: 4_000), Self.page(width: 800, height: 500)])
        await share.share()
        let files = try #require(presenter.presented.first)
        try #require(files.count == 2)
        #expect(try size(of: files[0]) == CGSize(width: 3_000, height: 2_000))
        #expect(try size(of: files[1]) == CGSize(width: 800, height: 500))
    }

    @Test func everyPageIsMarked() async throws {
        let share = try await model(pages: [Self.page(), Self.page(), Self.page()])
        await share.share()
        let files = try #require(presenter.presented.first)
        try #require(files.count == 3)
        for url in files {
            let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
            let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
            let cells = try WatermarkRendererTests.Pixels(image).strongestDifference(from: 1, columns: 3, rows: 2)
            #expect(cells.allSatisfy { $0 > 0.1 }, "\(url.lastPathComponent)")
        }
    }

    @Test func aPageThatFailsSharesNothing() async throws {
        let share = try await model(pages: [Self.page(), Self.page(), Self.page()])
        try await store.setUnreadablePage(#require(share.document.pageIDs.last))
        await share.share()
        #expect(presenter.presented.isEmpty)
        #expect(share.problem == .pageUnavailable)
        #expect(share.phase == .editing)
        #expect(leftFiles().isEmpty)
    }

    @Test func copiesAreHandedOverAsFiles() async throws {
        let counts = Counts()
        let share = try await model(counts: counts)
        await share.share()
        let files = try #require(presenter.presented.first)
        #expect(files.count == 2)
        #expect(files.allSatisfy { $0.isFileURL })
        #expect(presenter.filesExisted == [true])
        let root = temporary.appending(path: SharedCopies.folderName).standardizedFileURL.path
        #expect(files.allSatisfy { $0.standardizedFileURL.path.hasPrefix(root) })
        #expect(files.map(\.lastPathComponent).allSatisfy { $0.hasSuffix(".jpg") })
        #expect(share.phase == .shareSheetUp)
        #expect(counts.shown == 1)
    }

    @Test func aFullDiskSharesNothingAndLeavesNoFile() async throws {
        let full: SharedCopies.Write = { data, url in
            // The first page is written; the disk fills on the second.
            if url.lastPathComponent.contains("halaman 2") { throw CocoaError(.fileWriteOutOfSpace) }
            try SharedCopies.writeComplete(data, url)
        }
        let share = try await model(writeFile: full)
        await share.share()
        #expect(presenter.presented.isEmpty)
        #expect(share.problem == .storageFull)
        #expect(leftFiles().isEmpty)
    }

    @Test func theFolderIsEmptiedOnCompletion() async throws {
        let counts = Counts()
        let share = try await model(counts: counts)
        await share.share()
        #expect(leftFiles().count == 2)
        presenter.close(taken: true)
        #expect(leftFiles().isEmpty)
        #expect(share.phase == .closed)
        #expect(counts.ended == 1)
    }

    /// A target the share sheet copies for leaves its copy in tmp; it goes once the sheet has closed.
    @Test func theShareSheetsOwnCopiesAreDeletedOnCompletion() async throws {
        let share = try await model()
        await share.share()
        let sheetCopy = temporary.appending(path: "\(SharedCopies.shareSheetPrefix)-test", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: sheetCopy, withIntermediateDirectories: true)
        try Data("page".utf8).write(to: sheetCopy.appending(path: "page.jpg"))
        let other = temporary.appending(path: "com.apple.Other")
        try Data().write(to: other)
        presenter.close(taken: true)
        #expect(!FileManager.default.fileExists(atPath: sheetCopy.path))
        #expect(FileManager.default.fileExists(atPath: other.path))
    }

    @Test func aFullDiskWhileMakingTheFolderIsStorageFull() async throws {
        final class FullDisk: FileProtector {
            func protect(_ url: URL, as protection: FileProtectionClass) throws {
                throw CocoaError(.fileWriteOutOfSpace)
            }
        }
        let share = try await model(protector: FullDisk())
        await share.share()
        #expect(share.problem == .storageFull)
        #expect(presenter.presented.isEmpty)
    }

    @Test func theFolderIsEmptiedOnCancel() async throws {
        let share = try await model()
        await share.share()
        #expect(leftFiles().count == 2)
        presenter.close(taken: false)
        #expect(leftFiles().isEmpty)
    }

    // MARK: - The purpose

    @Test func aCancelKeepsThePurpose() async throws {
        let share = try await model()
        share.purpose = "Bank BCA"
        await share.share()
        presenter.close(taken: false)
        #expect(share.purpose == "Bank BCA")
        #expect(share.phase == .editing)
        #expect(share.canShare)
    }

}
