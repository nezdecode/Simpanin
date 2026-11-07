//
//  FakeDocuments.swift
//  SimpaninTests
//
//  Created by Inez Amanda on 7/11/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

@testable import Simpanin
@testable import VaultCore

/// Stands in for VaultStore's document calls, with documents kept in memory.
actor FakeDocuments {
    private var live: [Document] = []
    private var bin: [Document] = []
    private(set) var created: [DocumentFields] = []
    private(set) var createdPages: [[Data]] = []
    private var failure: VaultError?
    private var loadFailure: VaultError?
    private var binFailure: VaultError?
    private var createGated = false
    private var createGate: CheckedContinuation<Void, Never>?
    private var missingOnce: Set<DocumentID> = []
    private var fieldsByID: [DocumentID: DocumentFields] = [:]
    private var unreadable: Set<DocumentID> = []
    /// Every fields read, in order, so a test sees which documents were decrypted.
    private(set) var fieldReads: [DocumentID] = []
    private var readGated = false
    private var readGate: CheckedContinuation<Void, Never>?
    private var pagesByID: [PageID: Data] = [:]
    private var unreadablePages: Set<PageID> = []
    /// Every page read, in order, so a test sees they're read one at a time.
    private(set) var pageReads: [PageID] = []
    private var pageReadGated = false
    private var pageReadGate: CheckedContinuation<Void, Never>?

    func setFailure(_ failure: VaultError?) { self.failure = failure }
    func setUnreadable(_ id: DocumentID) { unreadable.insert(id) }
    func setReadable(_ id: DocumentID) { unreadable.remove(id) }
    func setUnreadablePage(_ id: PageID) { unreadablePages.insert(id) }

    /// Every call from now on fails as a locked vault does.
    func lock() {
        failure = .locked
        loadFailure = .locked
        binFailure = .locked
    }

    /// The next fields read waits until the test releases it, like a check still running.
    func gateNextFieldsRead() { readGated = true }

    /// False if no gated read started within two seconds, so a test fails instead of hanging.
    func waitUntilReadingFields() async -> Bool {
        for _ in 0..<2_000 where readGate == nil {
            try? await Task.sleep(for: .milliseconds(1))
        }
        return readGate != nil
    }

    func releaseFieldsRead() {
        readGate?.resume()
        readGate = nil
    }

    /// The next page read waits until the test releases it, like a page still decrypting.
    func gateNextPageRead() { pageReadGated = true }

    /// False if no gated page read started within two seconds, so a test fails instead of hanging.
    func waitUntilReadingPage() async -> Bool {
        for _ in 0..<2_000 where pageReadGate == nil {
            try? await Task.sleep(for: .milliseconds(1))
        }
        return pageReadGate != nil
    }

    func releasePageRead() {
        pageReadGate?.resume()
        pageReadGate = nil
    }
    func setLoadFailure(_ failure: VaultError?) { loadFailure = failure }
    func setBinFailure(_ failure: VaultError?) { binFailure = failure }
    /// The next createDocument waits until the test releases it, like a save still being written.
    func gateNextCreate() { createGated = true }

    /// False if no gated create started within two seconds, so a test fails instead of hanging.
    func waitUntilCreating() async -> Bool {
        for _ in 0..<2_000 where createGate == nil {
            try? await Task.sleep(for: .milliseconds(1))
        }
        return createGate != nil
    }

    func releaseCreate() {
        createGate?.resume()
        createGate = nil
    }

    /// The next reload sees the document in neither list, like a restore landing between its two reads.
    func missFromNextReload(_ id: DocumentID) { missingOnce.insert(id) }

    func documents() async throws -> [Document] {
        if let loadFailure { throw loadFailure }
        return live.filter { !missingOnce.contains($0.id) }
    }

    func recentlyDeleted() async throws -> [Document] {
        if let failure = loadFailure ?? binFailure { throw failure }
        defer { missingOnce = [] }
        return bin.filter { !missingOnce.contains($0.id) }
    }

    func fields(of id: DocumentID) async throws -> DocumentFields {
        if readGated {
            readGated = false
            await withCheckedContinuation { readGate = $0 }
        }
        if failure == .locked { throw VaultError.locked }
        fieldReads.append(id)
        if unreadable.contains(id) { throw VaultError.authenticationFailed }
        guard let fields = fieldsByID[id] else { throw VaultError.documentNotFound }
        return fields
    }

    // swiftlint:disable:next function_parameter_count - mirrors VaultStore.createDocument
    func createDocument(
        type: DocumentType, label: String?, expiry: CalendarDate?, pinned: Bool, fields: DocumentFields,
        pages: [Data]
    ) async throws -> DocumentID {
        if createGated {
            createGated = false
            await withCheckedContinuation { createGate = $0 }
        }
        if let failure { throw failure }
        let id = DocumentID()
        created.append(fields)
        createdPages.append(pages)
        fieldsByID[id] = fields
        let pageIDs = pages.map { _ in PageID() }
        for (pageID, data) in zip(pageIDs, pages) { pagesByID[pageID] = data }
        live.append(
            Document(
                id: id, type: type, label: label, createdAt: .now, updatedAt: .now, expiry: expiry, pinned: pinned,
                deletedAt: nil, pageIDs: pageIDs))
        return id
    }

    func delete(_ id: DocumentID) async throws {
        if let failure { throw failure }
        guard let index = live.firstIndex(where: { $0.id == id }) else { return }
        var document = live.remove(at: index)
        document.deletedAt = .now
        bin.append(document)
    }

    /// Gone for good, as VaultCore purges Baru dihapus after 30 days.
    func purge(_ id: DocumentID) {
        live.removeAll { $0.id == id }
        bin.removeAll { $0.id == id }
        fieldsByID[id] = nil
    }

    func restore(_ id: DocumentID) async throws {
        if let failure { throw failure }
        guard let index = bin.firstIndex(where: { $0.id == id }) else { return }
        var document = bin.remove(at: index)
        document.deletedAt = nil
        live.append(document)
    }

    /// Refuses a live document, as VaultStore does.
    func deletePermanently(_ id: DocumentID) async throws {
        if let failure { throw failure }
        guard bin.contains(where: { $0.id == id }) else { throw VaultError.documentNotDeleted }
        purge(id)
    }
}

extension FakeDocuments {
    func pageData(_ pageID: PageID, of id: DocumentID) async throws -> Data {
        if failure == .locked { throw VaultError.locked }
        pageReads.append(pageID)
        if pageReadGated {
            pageReadGated = false
            await withCheckedContinuation { pageReadGate = $0 }
        }
        // Baru dihapus's pages too, as VaultStore reads them.
        guard (live + bin).contains(where: { $0.id == id && $0.pageIDs.contains(pageID) }), let data = pagesByID[pageID]
        else { throw VaultError.pageNotFound }
        if unreadablePages.contains(pageID) { throw VaultError.authenticationFailed }
        return data
    }
}

extension FakeDocuments: DocumentStoring, PageReading {}  // in an extension, see FakeVault
