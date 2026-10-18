//
//  FullDiskTests.swift
//  VaultCoreTests
//
//  Created by Inez Amanda on 13/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import Testing

@testable import VaultCore

/// A full phone must never lock the user out: open() unlocks with what it loaded and leaves
/// the write it couldn't do for later.
@Suite("Full disk during open")
struct FullDiskTests {
    func makeStore(_ vault: TestVault, _ protector: FailingProtector) -> VaultStore {
        VaultStore(
            rootDirectory: vault.root, projectionURL: vault.projectionURL, keyStore: vault.keyStore,
            clock: vault.clock, fileProtector: protector)
    }

    func diskFullOnIndex() -> FailingProtector {
        FailingProtector(failingOn: "index.enc", with: CocoaError(.fileWriteOutOfSpace))
    }

    @Test func fullDiskDuringTheRepairSaveOpensAndNeverRotatesTheBadIndex() async throws {
        let vault = try TestVault()
        let protector = diskFullOnIndex()
        let store = makeStore(vault, protector)
        try await store.open()
        let id = try await store.createDocument(
            type: .ktp, expiry: nil, pinned: false, fields: Synthetic.ktpFields, pages: [Synthetic.page("front")])
        try await store.editDocument(id, type: .ktp, label: nil, expiry: nil, pinned: true, fields: Synthetic.ktpFields)
        // A damaged index.enc, so the next open loads index.prev.enc and has to write a new one.
        var damaged = try Data(contentsOf: vault.indexURL)
        damaged[damaged.count / 2] ^= 0x01
        try damaged.write(to: vault.indexURL)
        let goodPrevious = try Data(contentsOf: vault.previousIndexURL)

        protector.arm(true)
        let full = makeStore(vault, protector)
        let report = try await full.open()
        #expect(report.repairWaitingForSpace)
        #expect(report.indexSource == .previous)
        #expect(try await full.fields(of: id) == Synthetic.ktpFields)
        #expect(try Data(contentsOf: vault.previousIndexURL) == goodPrevious)

        // Space is freed and the user saves. The bad index.enc is replaced, never moved over
        // the good index.prev.enc.
        protector.arm(false)
        try await full.editDocument(id, type: .ktp, label: nil, expiry: nil, pinned: false, fields: Synthetic.ktpFields)
        #expect(try Data(contentsOf: vault.previousIndexURL) == goodPrevious)

        let reopened = vault.makeStore()
        let after = try await reopened.open()
        #expect(after.indexSource == .current)
        #expect(!after.repairWaitingForSpace)
        #expect(try await reopened.fields(of: id) == Synthetic.ktpFields)
        #expect(try await reopened.document(id).pageIDs.count == 1)
    }

    @Test func fullDiskDuringThePurgeInOpenOpensAndPurgesLater() async throws {
        let vault = try TestVault()
        let store = vault.makeStore()
        try await store.open()
        let id = try await store.createDocument(
            type: .ktp, expiry: nil, pinned: false, fields: Synthetic.ktpFields, pages: [Synthetic.page("front")])
        try await store.delete(id)
        vault.clock.advance(by: 31 * 86_400)

        let protector = diskFullOnIndex()
        protector.arm(true)
        let full = makeStore(vault, protector)
        let report = try await full.open()
        #expect(report.repairWaitingForSpace)
        #expect(report.purgedDocuments == 0)
        #expect(try await full.recentlyDeleted().map(\.id) == [id])

        protector.arm(false)
        let later = try await vault.makeStore().open()
        #expect(later.purgedDocuments == 1)
        #expect(!later.repairWaitingForSpace)
    }

    @Test func fullDiskWhileCreatingAVaultStillFails() async throws {
        // Nothing is loaded yet, so there's nothing to unlock with.
        let vault = try TestVault()
        let protector = FailingProtector(failingOn: "vault.json", with: CocoaError(.fileWriteOutOfSpace))
        protector.arm(true)
        await #expect(throws: VaultError.storageFull) { try await makeStore(vault, protector).open() }
    }
}
