//
//  VaultStoreTests.swift
//  VaultCoreTests
//
//  Created by Inez Amanda on 4/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import Testing

@testable import VaultCore

@Suite("VaultStore lifecycle")
struct VaultStoreTests {
    @Test func newVaultCreatesHeaderIndexAndProjection() async throws {
        let vault = try TestVault()
        let report = try await vault.makeStore().open()
        #expect(report.createdVault)
        #expect(!report.newestChangeMayBeLost)
        #expect(!report.recoveredFromPages)
        let header = try vault.header()
        #expect(header.formatVersion == 1)
        #expect(header.keySlots.map(\.kind) == [.device])
        #expect(FileManager.default.fileExists(atPath: vault.indexURL.path))
        #expect(try vault.projection().documents.isEmpty)
        #expect(await vault.keyStore.createCount == 1)

        // Reopening the same vault uses the existing key.
        let again = try await vault.makeStore().open()
        #expect(!again.createdVault)
        #expect(again.indexSource == .current)
        #expect(!again.newestChangeMayBeLost)
        #expect(!again.recoveredFromPages)
        #expect(await vault.keyStore.createCount == 1)
    }

    @Test func createAndReadDocument() async throws {
        let vault = try TestVault()
        let store = vault.makeStore()
        try await store.open()
        let pages = [Synthetic.page("ktp-front"), Synthetic.page("ktp-back")]
        let id = try await store.createDocument(
            type: .ktp, expiry: nil, pinned: true,
            fields: Synthetic.ktpFields, pages: pages)

        let doc = try await store.document(id)
        #expect(doc.type == .ktp)
        #expect(doc.pinned)
        #expect(doc.deletedAt == nil)
        #expect(doc.pageIDs.count == 2)
        #expect(try await store.fields(of: id) == Synthetic.ktpFields)
        #expect(try await store.pages(of: id).map(\.data) == pages)
        #expect(try await store.page(doc.pageIDs[1], of: id).data == pages[1])

        // Survives a reopen.
        let reopened = vault.makeStore()
        try await reopened.open()
        #expect(try await reopened.snapshot() == store.snapshot())
    }

    @Test func editFieldsTypeAndExpiry() async throws {
        let vault = try TestVault()
        let store = vault.makeStore()
        try await store.open()
        let id = try await store.createDocument(
            type: .other, expiry: nil, pinned: false,
            fields: DocumentFields(), pages: [Synthetic.page("sim")])
        let created = try await store.document(id)
        vault.clock.advance(by: 60)

        try await store.editDocument(
            id, type: .sim, expiry: Synthetic.simExpiry, pinned: true,
            fields: Synthetic.simFields)
        let edited = try await store.document(id)
        #expect(edited.type == .sim)
        #expect(edited.expiry == Synthetic.simExpiry)
        #expect(edited.pinned)
        #expect(edited.createdAt == created.createdAt)
        #expect(edited.updatedAt > created.updatedAt)
        #expect(try await store.fields(of: id) == Synthetic.simFields)
        #expect(
            try vault.projection().documents
                == [ProjectionEntry(id: id, type: .sim, expiry: Synthetic.simExpiry, reminderOffsets: [60, 30, 7])])
    }

    @Test func addAndReplacePages() async throws {
        let vault = try TestVault()
        let store = vault.makeStore()
        try await store.open()
        let id = try await store.createDocument(
            type: .passport, expiry: nil, pinned: false,
            fields: DocumentFields(), pages: [Synthetic.page("p1")])
        let added = try await store.addPage(Synthetic.page("p2"), to: id)
        #expect(try await store.document(id).pageIDs.last == added)

        let first = try await store.document(id).pageIDs[0]
        let replacement = try await store.replacePage(first, of: id, with: Synthetic.page("p1-rescan"))
        let doc = try await store.document(id)
        #expect(doc.pageIDs == [replacement, added])
        #expect(try await store.pages(of: id).map(\.data) == [Synthetic.page("p1-rescan"), Synthetic.page("p2")])
        // The old page file is deleted after the index points away from it.
        #expect(!FileManager.default.fileExists(atPath: vault.pageURL(first).path))
        #expect(try vault.pageFiles().count == 2)
    }

    @Test func softDeleteAndRestore() async throws {
        let vault = try TestVault()
        let store = vault.makeStore()
        try await store.open()
        let id = try await store.createDocument(
            type: .sim, expiry: Synthetic.simExpiry, pinned: false,
            fields: Synthetic.simFields, pages: [Synthetic.page("sim")])
        #expect(try vault.projection().documents.map(\.id) == [id])

        try await store.delete(id)
        #expect(try await store.documents().isEmpty)
        #expect(try await store.recentlyDeleted().map(\.id) == [id])
        #expect(try await store.document(id).deletedAt != nil)
        #expect(try vault.projection().documents.isEmpty)
        // Keys and files stay while in Recently deleted.
        #expect(try await store.pages(of: id).count == 1)
        #expect(try await store.fields(of: id) == Synthetic.simFields)

        try await store.restore(id)
        #expect(try await store.documents().map(\.id) == [id])
        #expect(try await store.recentlyDeleted().isEmpty)
        #expect(try vault.projection().documents.map(\.id) == [id])
    }

    @Test func deletingTwiceChangesNothing() async throws {
        let vault = try TestVault()
        let store = vault.makeStore()
        try await store.open()
        let id = try await store.createDocument(
            type: .sim, expiry: Synthetic.simExpiry, pinned: false,
            fields: Synthetic.simFields, pages: [Synthetic.page("sim")])
        try await store.delete(id)
        let deletedAt = try await store.document(id).deletedAt
        let filesBefore = try TestVault.files(in: vault.base)
        vault.clock.advance(by: 5 * 86_400)

        try await store.delete(id)
        // The 30-day timer does not restart, and no new index generation is written.
        #expect(try await store.document(id).deletedAt == deletedAt)
        #expect(try TestVault.files(in: vault.base) == filesBefore)
    }

    @Test func restoringALiveDocumentChangesNothing() async throws {
        let vault = try TestVault()
        let store = vault.makeStore()
        try await store.open()
        let id = try await store.createDocument(
            type: .sim, expiry: Synthetic.simExpiry, pinned: false,
            fields: Synthetic.simFields, pages: [Synthetic.page("sim")])
        let before = try TestVault.files(in: vault.base)
        let generation = try await vault.readIndex(at: vault.indexURL).generation
        vault.clock.advance(by: 60)

        try await store.restore(id)
        #expect(try TestVault.files(in: vault.base) == before)
        #expect(try await vault.readIndex(at: vault.indexURL).generation == generation)
        #expect(try await store.document(id).deletedAt == nil)
    }

    @Test func deletedDocumentRejectsEditsAndPageChanges() async throws {
        let vault = try TestVault()
        let store = vault.makeStore()
        try await store.open()
        let id = try await store.createDocument(
            type: .sim, expiry: Synthetic.simExpiry, pinned: false,
            fields: Synthetic.simFields, pages: [Synthetic.page("sim")])
        let page = try await store.document(id).pageIDs[0]
        try await store.delete(id)
        let filesBefore = try TestVault.files(in: vault.base)

        await #expect(throws: VaultError.documentDeleted) {
            try await store.editDocument(id, type: .sim, expiry: nil, pinned: true, fields: Synthetic.simFields)
        }
        await #expect(throws: VaultError.documentDeleted) { try await store.addPage(Synthetic.page("x"), to: id) }
        await #expect(throws: VaultError.documentDeleted) {
            try await store.replacePage(page, of: id, with: Synthetic.page("x"))
        }
        #expect(try TestVault.files(in: vault.base) == filesBefore)

        // After restoring, editing works again.
        try await store.restore(id)
        try await store.editDocument(id, type: .sim, expiry: nil, pinned: true, fields: Synthetic.simFields)
        #expect(try await store.document(id).pinned)
    }

    @Test func pageHeadersCarryTheirPosition() async throws {
        let vault = try TestVault()
        let store = vault.makeStore()
        try await store.open()
        let id = try await store.createDocument(
            type: .passport, expiry: nil, pinned: false, fields: DocumentFields(),
            pages: [Synthetic.page("p0"), Synthetic.page("p1")])
        _ = try await store.addPage(Synthetic.page("p2"), to: id)
        let first = try await store.document(id).pageIDs[0]
        _ = try await store.replacePage(first, of: id, with: Synthetic.page("p0-rescan"))  // keeps position 0

        let positions = try await store.document(id).pageIDs.map { pageID in
            try PageFile(decoding: Data(contentsOf: vault.pageURL(pageID))).header.position
        }
        #expect(positions == [0, 1, 2])
    }

    @Test func projectionUsesInjectedReminderOffsets() async throws {
        let vault = try TestVault()
        let store = VaultStore(
            rootDirectory: vault.root, projectionURL: vault.projectionURL,
            keyStore: vault.keyStore, clock: vault.clock, reminderOffsets: [90, 14])
        try await store.open()
        _ = try await store.createDocument(
            type: .stnk, expiry: Synthetic.simExpiry, pinned: false,
            fields: DocumentFields(), pages: [])
        #expect(try vault.projection().documents.map(\.reminderOffsets) == [[90, 14]])
    }
}

@Suite("VaultStore when locked, and limits")
struct VaultStoreLimitTests {
    @Test func lockedStoreRefusesAccess() async throws {
        let vault = try TestVault()
        let store = vault.makeStore()
        await #expect(throws: VaultError.locked) { try await store.documents() }
        try await store.open()
        let id = try await store.createDocument(
            type: .ktp, expiry: nil, pinned: false,
            fields: Synthetic.ktpFields, pages: [Synthetic.page("k")])
        await store.lock()
        await #expect(throws: VaultError.locked) { try await store.fields(of: id) }
        await #expect(throws: VaultError.locked) { try await store.pages(of: id) }
        try await store.open()
        #expect(try await store.fields(of: id) == Synthetic.ktpFields)
    }

    @Test func lockedStoreRefusesEveryWrite() async throws {
        let vault = try TestVault()
        let store = vault.makeStore()
        try await store.open()
        let ktp = try await store.createDocument(
            type: .ktp, expiry: nil, pinned: false, fields: Synthetic.ktpFields,
            pages: [Synthetic.page("a")])
        let sim = try await store.createDocument(
            type: .sim, expiry: nil, pinned: false, fields: Synthetic.simFields,
            pages: [Synthetic.page("b")])
        try await store.delete(sim)
        let page = try await store.document(ktp).pageIDs[0]
        await store.lock()
        vault.clock.advance(by: 40 * 86_400)  // the SIM would be due for purge
        let before = try TestVault.files(in: vault.base)

        await #expect(throws: VaultError.locked) {
            try await store.createDocument(type: .ktp, expiry: nil, pinned: false, fields: DocumentFields(), pages: [])
        }
        await #expect(throws: VaultError.locked) {
            try await store.editDocument(ktp, type: .ktp, expiry: nil, pinned: true, fields: DocumentFields())
        }
        await #expect(throws: VaultError.locked) { try await store.addPage(Synthetic.page("x"), to: ktp) }
        await #expect(throws: VaultError.locked) {
            try await store.replacePage(page, of: ktp, with: Synthetic.page("x"))
        }
        await #expect(throws: VaultError.locked) { try await store.delete(ktp) }
        await #expect(throws: VaultError.locked) { try await store.restore(sim) }
        await #expect(throws: VaultError.locked) { try await store.deletePermanently(ktp) }
        await #expect(throws: VaultError.locked) { try await store.purgeExpired() }
        #expect(try TestVault.files(in: vault.base) == before)
    }

    @Test func concurrentOpensCreateOneVault() async throws {
        let vault = try TestVault()
        let store = vault.makeStore()
        async let first = store.open()
        async let second = store.open()
        let reports = try await [first, second]
        #expect(reports[0] == reports[1])
        #expect(reports[0].createdVault)
        #expect(await vault.keyStore.createCount == 1)
        #expect(try TestVault.files(in: vault.root).keys.filter { $0 == "vault.json" }.count == 1)
    }

    @Test func fifteenMegabytePage() async throws {
        let vault = try TestVault()
        let store = vault.makeStore()
        try await store.open()
        let started = ContinuousClock.now
        let big = Synthetic.largePage(bytes: 15_000_000)
        let id = try await store.createDocument(
            type: .passport, expiry: nil, pinned: false, fields: DocumentFields(),
            pages: [big])
        let pageID = try await store.document(id).pageIDs[0]
        #expect(try await store.page(pageID, of: id).data == big)

        var file = try Data(contentsOf: vault.pageURL(pageID))
        file[file.count / 2] ^= 0x01
        try file.write(to: vault.pageURL(pageID))
        await #expect(throws: VaultError.authenticationFailed) { try await store.page(pageID, of: id) }
        print("LARGE PAGE TEST: 15 MB round trip and tamper in \(ContinuousClock.now - started)")
    }

    @Test func unknownIdsAreReported() async throws {
        let vault = try TestVault()
        let store = vault.makeStore()
        try await store.open()
        await #expect(throws: VaultError.documentNotFound) { try await store.fields(of: DocumentID()) }
        let id = try await store.createDocument(
            type: .ktp, expiry: nil, pinned: false,
            fields: Synthetic.ktpFields, pages: [Synthetic.page("k")])
        await #expect(throws: VaultError.pageNotFound) { try await store.page(PageID(), of: id) }
        await #expect(throws: VaultError.pageNotFound) {
            try await store.replacePage(PageID(), of: id, with: Synthetic.page("k2"))
        }
        // A page the index lists but whose file is gone.
        let pageID = try await store.document(id).pageIDs[0]
        try FileManager.default.removeItem(at: vault.pageURL(pageID))
        await #expect(throws: VaultError.pageNotFound) { try await store.page(pageID, of: id) }
    }

    @Test func timestampsAreWholeSeconds() async throws {
        let vault = try TestVault(clock: TestClock(Date(timeIntervalSince1970: 1_790_000_000.75)))
        let store = vault.makeStore()
        try await store.open()
        let id = try await store.createDocument(
            type: .ktp, expiry: nil, pinned: false,
            fields: Synthetic.ktpFields, pages: [])
        #expect(try await store.document(id).createdAt == Date(timeIntervalSince1970: 1_790_000_000))
    }
}
