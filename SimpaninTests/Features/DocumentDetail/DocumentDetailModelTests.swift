//
//  DocumentDetailModelTests.swift
//  SimpaninTests
//
//  Created by Inez Amanda on 28/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import Testing
import UIKit
import VaultCore

@testable import Simpanin

/// Synthetic values only; NIKs start with 00.
@MainActor
@Suite("Document screen model")
struct DocumentDetailModelTests {
    static let ktpFields = DocumentFields([
        FieldKey.nik: "0012341708900001", FieldKey.name: "BUDI CONTOH", FieldKey.birthDate: "1990-08-17",
    ])

    let store = FakeDocuments()
    let clipboard = FakeClipboard()

    /// A page as a camera might give it, larger than the pager needs.
    static func page(width: Int = 3_000, height: Int = 2_000) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).pngData {
            $0.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    func model(
        _ type: DocumentType = .ktp, fields: DocumentFields = ktpFields, pages: [Data]? = nil,
        onDelete: @escaping (DocumentID) async -> Bool = { _ in true }
    ) async throws -> DocumentDetailModel {
        let id = try await store.createDocument(
            type: type, label: nil, expiry: nil, pinned: false, fields: fields, pages: pages ?? [Self.page()])
        let document = try #require(await store.documents().first { $0.id == id })
        return DocumentDetailModel(
            document: document, store: store, pageReader: store, clipboard: clipboard, onDelete: onDelete)
    }

    func loaded(_ type: DocumentType = .ktp, fields: DocumentFields = ktpFields) async throws -> DocumentDetailModel {
        let detail = try await model(type, fields: fields)
        await detail.load()
        return detail
    }

    func value(_ detail: DocumentDetailModel, _ key: String) -> String? {
        detail.rows.first { $0.key == key }?.value
    }

    func shownCount(_ detail: DocumentDetailModel) -> Int {
        detail.pages.count { if case .shown = $0 { true } else { false } }
    }

    // MARK: Loading

    @Test func loadsFieldsAndPagesOnce() async throws {
        let detail = try await model(pages: [Self.page(), Self.page()])
        await detail.load()
        await detail.load()
        #expect(detail.phase == .loaded)
        #expect(await store.fieldReads.count == 1)
        #expect(await store.pageReads.count == 2)
        #expect(shownCount(detail) == 2)
    }

    @Test func readsPagesOneByOne() async throws {
        let detail = try await model(pages: [Self.page(), Self.page(), Self.page()])
        await detail.load()
        #expect(await store.pageReads == detail.document.pageIDs)
    }

    /// The pager never holds a page at full size; only the viewer decodes one.
    @Test func keepsOnlyReducedImages() async throws {
        let detail = try await model(pages: [Self.page(width: 3_000, height: 2_000)])
        await detail.load()
        guard case .shown(let image) = try #require(detail.pages.first) else {
            Issue.record("The page wasn't shown")
            return
        }
        #expect(max(image.width, image.height) == DocumentDetailModel.reducedPixelSize)
    }

    /// The viewer reads its page again, so the model never keeps a full-size one.
    @Test func theViewerReadsItsPageAgainAtFullSize() async throws {
        let detail = try await model(pages: [Self.page(width: 3_000, height: 2_000)])
        await detail.load()
        let image = try #require(await detail.fullPage(0))
        #expect(image.width == 3_000)
        #expect(await store.pageReads.count == 2)
        #expect(await detail.fullPage(1) == nil)
    }

    /// Pages are read one at a time, so one that can't be opened doesn't hide the others.
    @Test func failedPageLeavesOthers() async throws {
        let detail = try await model(pages: [Self.page(), Self.page()])
        await store.setUnreadablePage(detail.document.pageIDs[0])
        await detail.load()
        try #require(detail.pages.count == 2)
        guard case .failed = detail.pages[0], case .shown = detail.pages[1] else {
            Issue.record("Expected the first page failed and the second shown")
            return
        }
        #expect(detail.phase == .loaded)
    }

    @Test func noPagesShowsNoPager() async throws {
        let detail = try await model(pages: [])
        await detail.load()
        #expect(!detail.hasPages)
        #expect(detail.pages.isEmpty)
        #expect(detail.phase == .loaded)
    }

    @Test func failedFieldsShowsLoadFailed() async throws {
        let detail = try await model()
        await store.setUnreadable(detail.document.id)
        await detail.load()
        #expect(detail.phase == .failed)
        #expect(detail.rows.allSatisfy { $0.value == nil })
        #expect(await store.pageReads.isEmpty)
    }

    @Test func retryLoadsAgain() async throws {
        let detail = try await model()
        await store.setUnreadable(detail.document.id)
        await detail.load()
        await store.setReadable(detail.document.id)
        await detail.load()
        #expect(detail.phase == .loaded)
        #expect(value(detail, FieldKey.name) == "BUDI CONTOH")
    }

    @Test func aMissingDocumentGoesBack() async throws {
        let detail = try await model()
        await store.purge(detail.document.id)
        await detail.load()
        #expect(detail.phase == .gone)
    }

    /// The lock takes the screen away, so it shows no error on the way out.
    @Test func aLockWhileLoadingShowsNoError() async throws {
        let detail = try await model()
        await store.lock()
        await detail.load()
        #expect(detail.phase == .loading)
    }

    // MARK: The number

    @Test func numberStartsMasked() async throws {
        let detail = try await loaded()
        #expect(!detail.numberShown)
        #expect(value(detail, FieldKey.nik) == "0012 •••• •••• 0001")
        detail.toggleNumber()
        #expect(value(detail, FieldKey.nik) == "0012 3417 0890 0001")
    }

    @Test func revealMasksAgainWhenLeaving() async throws {
        let detail = try await loaded()
        detail.toggleNumber()
        #expect(detail.numberShown)
        detail.screenLeft()
        #expect(!detail.numberShown)
    }

    @Test func revealMasksAgainInBackground() async throws {
        let detail = try await loaded()
        detail.toggleNumber()
        #expect(detail.numberShown)
        detail.appLeftForeground()
        #expect(!detail.numberShown)
    }

    @Test func revealMasksAgainWhenThePageViewerOpens() async throws {
        let detail = try await loaded()
        detail.toggleNumber()
        #expect(detail.numberShown)
        detail.viewerOpened()
        #expect(!detail.numberShown)
    }

    // MARK: Fields and copying

    @Test func emptyNumberHasNoCopy() async throws {
        let detail = try await loaded(fields: DocumentFields([FieldKey.nik: " ", FieldKey.name: "BUDI CONTOH"]))
        let row = try #require(detail.rows.first { $0.key == FieldKey.nik })
        #expect(row.value == nil)
        #expect(!row.canCopy)
        #expect(String(localized: row.empty) == "NIK belum diisi")
        detail.copy(FieldKey.nik)
        #expect(clipboard.copied.isEmpty)
        #expect(detail.toast == nil)
    }

    @Test func emptyNameHasNoCopy() async throws {
        let detail = try await loaded(.simC, fields: DocumentFields([FieldKey.simNumber: "0000-0000-000001"]))
        let name = try #require(detail.rows.first { $0.key == FieldKey.name })
        #expect(name.value == nil)
        #expect(!name.canCopy)
        #expect(String(localized: name.empty) == "Nama belum diisi")
        let number = try #require(detail.rows.first { $0.key == FieldKey.simNumber })
        #expect(String(localized: number.title) == "Nomor SIM")
        let birth = try #require(detail.rows.first { $0.key == FieldKey.birthDate })
        #expect(String(localized: birth.empty) == "Belum diisi")
        detail.copy(FieldKey.name)
        #expect(clipboard.copied.isEmpty)
    }

    @Test func copyGivesDigitsOnly() async throws {
        let detail = try await loaded(.simC, fields: DocumentFields([FieldKey.simNumber: "0000-0000-000001"]))
        detail.copy(FieldKey.simNumber)
        #expect(clipboard.copied == ["00000000000001"])
        #expect(detail.toast.map { String(localized: $0.title) } == "Nomor SIM disalin")
        #expect(detail.toast?.detail.map { String(localized: $0) } == "Hilang dari clipboard dalam 60 detik")
    }

    @Test func copyNameAsStored() async throws {
        let detail = try await loaded()
        detail.copy(FieldKey.name)
        #expect(clipboard.copied == ["BUDI CONTOH"])
        #expect(detail.toast.map { String(localized: $0.title) } == "Nama disalin")
    }

    @Test func copyWhileMaskedStaysMasked() async throws {
        let detail = try await loaded()
        detail.copy(FieldKey.nik)
        #expect(clipboard.copied == ["0012341708900001"])
        #expect(!detail.numberShown)
        #expect(value(detail, FieldKey.nik) == "0012 •••• •••• 0001")
    }

    /// The toast says what was copied, never the number itself, also while it's shown.
    @Test func toastNeverContainsTheNumber() async throws {
        let detail = try await loaded()
        detail.toggleNumber()
        detail.copy(FieldKey.nik)
        let toast = try #require(detail.toast)
        let text = [toast.title, toast.detail].compactMap { $0.map { String(localized: $0) } }.joined()
        #expect(text.hasPrefix("NIK disalin"))
        #expect(!text.contains("0012"))
        #expect(!text.contains("0001"))
    }

    @Test func aSecondCopyReplacesTheToast() async throws {
        let detail = try await loaded()
        detail.copy(FieldKey.nik)
        let first = try #require(detail.toast)
        detail.copy(FieldKey.name)
        let second = try #require(detail.toast)
        #expect(first != second)
        #expect(String(localized: second.title) == "Nama disalin")
    }

    /// Only the type's own fields, in its order; a passport has none yet.
    @Test func unknownKeysNotShown() async throws {
        var values = Self.ktpFields.values
        values[FieldKey.simNumber] = "0000-0000-000001"
        values["address"] = "JL CONTOH"
        let detail = try await loaded(fields: DocumentFields(values))
        #expect(detail.rows.map(\.key) == [FieldKey.nik, FieldKey.name, FieldKey.birthDate])
        #expect(value(detail, FieldKey.birthDate) == "17-08-1990")
        let passport = try await loaded(.passport, fields: DocumentFields([FieldKey.name: "BUDI CONTOH"]))
        #expect(passport.rows.isEmpty)
    }

    @Test func deleteClosesOnlyWhenItSucceeded() async throws {
        var deleted: [DocumentID] = []
        var succeeds = false
        let detail = try await model(onDelete: { id in
            deleted.append(id)
            return succeeds
        })
        await detail.delete()
        #expect(!detail.closed)
        succeeds = true
        await detail.delete()
        #expect(detail.closed)
        #expect(deleted == [detail.document.id, detail.document.id])
    }
}
