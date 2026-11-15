//
//  PowerLossTests.swift
//  VaultCoreTests
//
//  Created by Inez Amanda on 15/11/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import Testing

@testable import VaultCore

/// A power cut, modelled as the worst case the design assumes: renames and new names survive,
/// but a file whose bytes were never flushed comes back empty. A file counts as on disk when its
/// bytes were there before the run or match the bytes of some flush, compared by content because
/// a rotation moves flushed bytes to another name.
@Suite("Power cut simulation")
struct PowerLossTests: FlushTesting {
    let crash = CrashTests()

    /// Empties every file in the vault folder whose bytes never reached the disk. A flush that threw
    /// doesn't count.
    func cutPower(_ vault: TestVault, onDiskBefore: [String: Data], _ flusher: RecordingFlusher) throws {
        let onDisk = Set(onDiskBefore.values).union(flusher.recorded.filter { !$0.failed }.map(\.contents))
        for (path, data) in try TestVault.files(in: vault.root) where !onDisk.contains(data) {
            try Data().write(to: vault.root.appending(path: path))
        }
    }

    func recordingStore(_ vault: TestVault, crash: CrashSwitch? = nil) -> (VaultStore, RecordingFlusher) {
        let flusher = RecordingFlusher(pagesDirectory: vault.pagesDirectory)
        return (vault.makeStore(crash: crash, flusher: flusher), flusher)
    }

    /// The audit's case: two saves a few seconds apart, then the power goes.
    @Test func twoSavesThenAPowerCutKeepBothChanges() async throws {
        let vault = try TestVault()
        let first = vault.makeStore()
        try await first.open()
        let id = try await first.createDocument(
            type: .ktp, expiry: nil, pinned: false, fields: Synthetic.ktpFields, pages: [Synthetic.page("front")])
        let onDiskBefore = try TestVault.files(in: vault.root)

        let (store, flusher) = recordingStore(vault)
        try await store.open()
        try await store.editDocument(
            id, type: .ktp, label: "a", expiry: nil, pinned: false, fields: Synthetic.ktpFields)
        try await store.editDocument(id, type: .ktp, label: "a", expiry: nil, pinned: true, fields: Synthetic.ktpFields)
        try cutPower(vault, onDiskBefore: onDiskBefore, flusher)

        let reopened = vault.makeStore()
        let report = try await reopened.open()
        #expect(report.indexSource == .current)
        #expect(!report.newestChangeMayBeLost)
        let document = try await reopened.document(id)
        #expect(document.label == "a" && document.pinned)
        #expect(try await reopened.fields(of: id) == Synthetic.ktpFields)
    }

    /// What a reopen shows after the power went between an index write and its flush: the state
    /// before the save, plus the new pages, which were flushed first and are re-attached.
    func stateBetweenWriteAndFlush(
        _ operation: CrashTests.Operation, before: [DocumentSnapshot], reopenedAt now: Date
    ) throws -> [DocumentSnapshot] {
        var documents = before
        let ktp = try #require(documents.firstIndex { $0.type == DocumentType.ktp.rawValue })
        switch operation {
        case .create:
            let stamp = Date(timeIntervalSince1970: now.timeIntervalSince1970.rounded(.down))
            documents.append(
                DocumentSnapshot(
                    type: DocumentType.other.rawValue, createdAt: stamp, updatedAt: stamp, expiry: nil, pinned: false,
                    deletedAt: nil, fields: [:], pages: [Synthetic.page("n1"), Synthetic.page("n2")]))
        case .addPage:
            documents[ktp].pages.append(Synthetic.page("a3"))
        case .replacePage:
            // Both pages claim the first position; the old one keeps its place.
            documents[ktp].pages.insert(Synthetic.page("a1-rescan"), at: 1)
        case .edit, .softDelete, .restore, .deletePermanently:
            break
        }
        return documents.sorted()
    }

    @Test(arguments: CrashTests.Operation.allCases)
    func aPowerCutAfterEachWriteStepKeepsWhatWasSaved(_ operation: CrashTests.Operation) async throws {
        let base = try await crash.makeBaseline()
        let simKey = try #require(
            try await base.vault.readIndex(at: base.vault.indexURL).documents.first { $0.id == base.sim }?.sealedKey)
        let before = try await base.vault.makeStore().snapshotAfterOpen()

        let dry = try await base.vault.copy()
        let recorder = CrashSwitch()
        let dryStore = dry.makeStore(crash: recorder)
        try await dryStore.open()
        recorder.arm()
        try await crash.perform(operation, on: dryStore, base)
        let after = try await dryStore.snapshot()
        let steps = recorder.steps
        let firstIndexWrite = try #require(steps.firstIndex(of: .indexWritten)) + 1

        for crashStep in 1...steps.count {
            let label = "\(operation.rawValue), power cut after step \(crashStep) (\(steps[crashStep - 1]))"
            let run = try await base.vault.copy()
            let onDiskBefore = try TestVault.files(in: run.root)
            let crashSwitch = CrashSwitch(crashAt: crashStep)
            let (store, flusher) = recordingStore(run, crash: crashSwitch)
            try await store.open()
            crashSwitch.arm()
            await #expect(throws: SimulatedCrash.self, "\(label)") {
                try await crash.perform(operation, on: store, base)
            }
            try cutPower(run, onDiskBefore: onDiskBefore, flusher)

            run.clock.advance(by: 3600)  // old enough for orphan cleanup
            let reopened = run.makeStore()
            let report = try await reopened.open()
            #expect(report.indexSource != .recovered, "\(label)")
            // Row 10's notice: the open fell back to index.prev.enc.
            if crashStep == firstIndexWrite { #expect(report.newestChangeMayBeLost, "\(label)") }
            if crashStep == steps.count { #expect(report.indexSource == .current, "\(label)") }
            let expected =
                if crashStep < firstIndexWrite {
                    before
                } else if crashStep == firstIndexWrite {
                    try stateBetweenWriteAndFlush(operation, before: before, reopenedAt: run.clock.now)
                } else {
                    after
                }
            #expect(try await reopened.snapshot() == expected, "\(label)")
            try await crash.expectConsistent(run, reopened, label)
            if operation == .deletePermanently, crashStep > firstIndexWrite {
                try await expectNoIndexHolds(simKey, in: run)
            }
        }
    }

    @Test func aPowerCutDuringThePurgeOnOpenNeverBringsTheDocumentBack() async throws {
        let base = try await crash.makeBaseline()
        let purgeTime = base.vault.clock.now + 30 * 86_400 + 1
        let sealedKey = try #require(
            try await base.vault.readIndex(at: base.vault.indexURL)
                .documents.first { $0.id == base.sim }?.sealedKey)

        let dry = try await base.vault.copy(clock: TestClock(purgeTime))
        let recorder = CrashSwitch()
        recorder.arm()
        #expect(try await dry.makeStore(crash: recorder).open().purgedDocuments == 1)
        let steps = recorder.steps

        for crashStep in 1...steps.count {
            let label = "purge on open, power cut after step \(crashStep) (\(steps[crashStep - 1]))"
            let run = try await base.vault.copy(clock: TestClock(purgeTime))
            let onDiskBefore = try TestVault.files(in: run.root)
            let crashSwitch = CrashSwitch(crashAt: crashStep)
            crashSwitch.arm()
            let (store, flusher) = recordingStore(run, crash: crashSwitch)
            await #expect(throws: SimulatedCrash.self, "\(label)") { try await store.open() }
            try cutPower(run, onDiskBefore: onDiskBefore, flusher)

            run.clock.advance(by: 3600)
            let reopened = run.makeStore()
            let report = try await reopened.open()
            #expect(report.indexSource != .recovered, "\(label)")
            await #expect(throws: VaultError.documentNotFound, "\(label)") { try await reopened.document(base.sim) }
            #expect(try await reopened.documents().map(\.id) == [base.ktp], "\(label)")
            try await crash.expectConsistent(run, reopened, label)
            try await expectNoIndexHolds(sealedKey, in: run)
        }
    }

    @Test func aPowerCutRightAfterTheFirstSaveKeepsTheVaultHeader() async throws {
        let vault = try TestVault()
        let (store, flusher) = recordingStore(vault)
        try await store.open()
        let id = try await store.createDocument(
            type: .ktp, expiry: nil, pinned: false, fields: Synthetic.ktpFields, pages: [Synthetic.page("front")])
        try cutPower(vault, onDiskBefore: [:], flusher)

        let reopened = vault.makeStore()
        let report = try await reopened.open()
        #expect(report.indexSource == .current)
        #expect(try await reopened.fields(of: id) == Synthetic.ktpFields)
        #expect(try await reopened.pages(of: id).map(\.data) == [Synthetic.page("front")])
    }
}
