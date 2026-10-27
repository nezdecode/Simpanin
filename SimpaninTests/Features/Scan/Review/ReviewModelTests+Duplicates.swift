//
//  ReviewModelTests+Duplicates.swift
//  SimpaninTests
//
//  Created by Inez Amanda on 27/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import Parsers
import Testing
import VaultCore

@testable import Simpanin

/// Simpan when the vault already holds the same KTP or SIM.
extension ReviewModelTests {
    /// A store already holding the KTP that `ktp` reads.
    func storeWithTheKTP() async throws -> FakeDocuments {
        let store = FakeDocuments()
        _ = try await store.createDocument(
            type: .ktp, label: nil, expiry: nil, pinned: false, fields: Self.ktp.fields, pages: [])
        return store
    }

    func saveDocument(_ type: DocumentType, _ values: [String: String], in store: FakeDocuments) async throws {
        _ = try await store.createDocument(
            type: type, label: nil, expiry: nil, pinned: false, fields: DocumentFields(values), pages: [])
    }

    @Test func aDuplicateStopsTheSaveAndAsks() async throws {
        let store = try await storeWithTheKTP()
        let review = model(store)
        review.load(Self.ktp, pages: [try page()])
        #expect(await !review.save())
        #expect(review.duplicate?.name == .ktp)
        #expect(review.saveError == nil)
        #expect(await store.created.count == 1)
    }

    /// Simpan asks about the pages first; the check runs only once Simpan goes on to save.
    @Test func theDuplicateQuestionComesLast() async throws {
        let review = model(try await storeWithTheKTP())
        try loadKTPAndSIM(into: review)
        #expect(review.saveStep() == .askPages)
        #expect(review.duplicate == nil)
        #expect(await !review.save())
        #expect(review.duplicate != nil)
    }

    @Test func simpanSajaWithAnEmptyNIKSkipsTheCheck() async throws {
        let store = FakeDocuments()
        try await saveDocument(.ktp, [:], in: store)
        let review = model(store)
        review.load(Self.ktp, pages: [try page()])
        review.setValue("", for: FieldKey.nik)
        #expect(await review.save())
        #expect(await store.fieldReads.isEmpty)
    }

    @Test func theEditedNumberIsCompared() async throws {
        let store = FakeDocuments()
        try await saveDocument(.ktp, [FieldKey.nik: "0012341708900002"], in: store)
        let review = model(store)
        review.load(Self.ktp, pages: [try page()])
        review.setValue("0012341708900002", for: FieldKey.nik)
        #expect(await !review.save())
        #expect(review.duplicate != nil)
    }

    /// The type picker moves no values, so the NIK of a SIM page saved as KTP is always typed.
    @Test func aSIMPageSavedAsKTPIsComparedWithKTPs() async throws {
        let review = model(try await storeWithTheKTP())
        review.load(Self.sim, pages: [try page()])
        review.type = .ktp
        review.setValue("0012341708900001", for: FieldKey.nik)
        #expect(await !review.save())
        #expect(review.duplicate?.name == .ktp)
    }

    @Test func simpanAfterTheWarningSavesWithoutCheckingAgain() async throws {
        let store = try await storeWithTheKTP()
        let review = model(store)
        review.load(Self.ktp, pages: [try page()])
        #expect(await !review.save())
        let reads = await store.fieldReads.count
        review.acceptDuplicate()
        #expect(await review.save())
        #expect(await store.fieldReads.count == reads)
        #expect(await store.created.count == 2)
    }

    @Test func aFailedSaveAfterTheWarningDoesntAskAgain() async throws {
        let store = try await storeWithTheKTP()
        let review = model(store)
        review.load(Self.ktp, pages: [try page()])
        #expect(await !review.save())
        review.acceptDuplicate()
        await store.setFailure(.storageFull)
        #expect(await !review.save())
        review.saveError = nil
        await store.setFailure(nil)
        #expect(await review.save())
        #expect(review.duplicate == nil)
    }

    @Test func anEditedNumberAfterTheWarningAsksAgain() async throws {
        let store = try await storeWithTheKTP()
        try await saveDocument(.ktp, [FieldKey.nik: "0012341708900002"], in: store)
        let review = model(store)
        review.load(Self.ktp, pages: [try page()])
        #expect(await !review.save())
        review.acceptDuplicate()
        review.setValue("0012341708900002", for: FieldKey.nik)
        #expect(await !review.save())
        #expect(review.duplicate != nil)
    }

    @Test func aChangedTypeAfterTheWarningAsksAgain() async throws {
        let store = FakeDocuments()
        // A classless SIM matches every class, so the second type is a duplicate too.
        try await saveDocument(.sim, Self.sim.fields.values, in: store)
        let review = model(store)
        review.load(Self.sim, pages: [try page()])
        #expect(await !review.save())
        review.acceptDuplicate()
        review.type = .simA
        #expect(await !review.save())
        #expect(review.duplicate != nil)
    }

    @Test func kembaliThenSimpanChecksAgain() async throws {
        let review = model(try await storeWithTheKTP())
        review.load(Self.ktp, pages: [try page()])
        #expect(await !review.save())
        review.duplicateAnswered()
        #expect(review.saveStep() == .save)
        #expect(await !review.save())
        #expect(review.duplicate != nil)
    }

    /// Between the check and its alert opening, Simpan stays tappable; a tap there starts nothing.
    @Test func aTapWhileTheWarningIsPendingStartsNoSecondCheck() async throws {
        let review = model(try await storeWithTheKTP())
        review.load(Self.ktp, pages: [try page()])
        #expect(await !review.save())
        #expect(review.saveStep() == nil)
        // The pages alert closing late resets the other questions, never this one.
        review.alertAnswered()
        #expect(review.saveStep() == nil)
    }

    @Test func kembaliOnTheWarningDoesntAskThePagesQuestionAgain() async throws {
        let review = model(try await storeWithTheKTP())
        try loadKTPAndSIM(into: review)
        #expect(review.saveStep() == .askPages)
        #expect(await !review.save())
        review.duplicateAnswered()
        review.alertAnswered()
        #expect(review.saveStep() == .save)
    }

    @Test func aTypeChangedAndBackDoesntAskThePagesQuestionAgain() async throws {
        let review = model(try await storeWithTheKTP())
        try loadKTPAndSIM(into: review)
        #expect(review.saveStep() == .askPages)
        #expect(await !review.save())
        review.duplicateAnswered()
        review.alertAnswered()
        review.type = .passport
        review.type = .ktp
        #expect(review.saveStep() == .save)
    }

    @Test func aChangedPageNoteAsksThePagesQuestionAgain() async throws {
        let review = model(try await storeWithTheKTP())
        try loadKTPAndSIM(into: review)
        #expect(review.saveStep() == .askPages)
        #expect(await !review.save())
        review.duplicateAnswered()
        review.alertAnswered()
        review.type = .passport
        #expect(review.pageNotes.saveWarning != nil)
        #expect(review.saveStep() == .askPages)
    }

    @Test func aRescanForgetsThePagesAnswer() async throws {
        let review = model(try await storeWithTheKTP())
        try loadKTPAndSIM(into: review)
        #expect(review.saveStep() == .askPages)
        #expect(await !review.save())
        review.duplicateAnswered()
        review.alertAnswered()
        try loadKTPAndSIM(into: review)
        #expect(review.saveStep() == .askPages)
    }

    @Test func aRescanForgetsTheWarning() async throws {
        let review = model(try await storeWithTheKTP())
        review.load(Self.ktp, pages: [try page()])
        #expect(await !review.save())
        review.load(Self.ktp, pages: [try page()])
        #expect(review.duplicate == nil)
        #expect(review.saveStep() == .save)
        // Nor is an earlier Simpan in the alert kept for the new scan.
        #expect(await !review.save())
        review.acceptDuplicate()
        review.load(Self.ktp, pages: [try page()])
        #expect(await !review.save())
        #expect(review.duplicate != nil)
    }

    @Test func aSecondTapDuringTheCheckSavesNothingTwice() async throws {
        let store = try await storeWithTheKTP()
        let review = model(store)
        review.load(Self.ktp, pages: [try page()])
        await store.gateNextFieldsRead()
        let first = Task { await review.save() }
        let reading = await store.waitUntilReadingFields()
        let second = await review.save()
        await store.releaseFieldsRead()
        try #require(reading)
        #expect(!second)
        #expect(await !first.value)
        #expect(await store.created.count == 1)
        #expect(await store.fieldReads.count == 1)
    }

    @Test func aLockDuringTheCheckEndsInTheLockedSaveWithoutAsking() async throws {
        let store = try await storeWithTheKTP()
        let review = model(store)
        review.load(Self.ktp, pages: [try page()])
        await store.gateNextFieldsRead()
        let saving = Task { await review.save() }
        let reading = await store.waitUntilReadingFields()
        await store.lock()
        await store.releaseFieldsRead()
        try #require(reading)
        #expect(await !saving.value)
        #expect(review.duplicate == nil)
        // A locked save says nothing here; the lock drops the scan and says so after unlocking.
        #expect(review.saveError == nil)
        #expect(await store.created.count == 1)
    }
}
