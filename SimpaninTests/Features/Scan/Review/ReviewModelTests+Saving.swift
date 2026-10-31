//
//  ReviewModelTests+Saving.swift
//  SimpaninTests
//
//  Created by Inez Amanda on 17/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import CoreGraphics
import Foundation
import Parsers
import Synchronization
import Testing
import VaultCore

@testable import Simpanin

/// What a save stores, and what it never stores.
extension ReviewModelTests {
    /// Encoding a few full-size pages takes long enough to freeze the screen, so it runs off the main actor.
    @Test func pagesAreEncodedOffTheMainActor() async throws {
        let review = model(encode: { _ in Thread.isMainThread ? nil : Data([1]) })
        review.loadScan(Self.ktp, pages: [try page()])
        #expect(await review.save())
    }

    /// What's saved is what the screen showed when Simpan was tapped, even if something changes while
    /// the pages are being encoded.
    @Test func aSaveKeepsWhatWasShownWhenItStarted() async throws {
        let store = FakeDocuments()
        let started = Mutex(false)
        let release = DispatchSemaphore(value: 0)
        let review = model(
            store,
            encode: { _ in
                started.withLock { $0 = true }
                _ = release.wait(timeout: .now() + 5)
                return Data([1])
            })
        review.loadScan(Self.ktp, pages: [try page()])
        let saving = Task { await review.save() }
        // The encode runs off the main actor; wait up to two seconds for it to start, never forever.
        for _ in 0..<2_000 where !started.withLock({ $0 }) {
            try await Task.sleep(for: .milliseconds(1))
        }
        let encoding = started.withLock { $0 }
        review.type = .simC
        review.label = "Later"
        release.signal()
        try #require(encoding)
        #expect(await saving.value)
        let document = try #require(try await store.documents().first)
        #expect(document.type == .ktp)
        #expect(document.label == nil)
    }

    /// A Paspor or STNK can be given its date by hand, as no parser reads one yet; only a SIM's missing
    /// date is marked, since only there a parser should have read it.
    @Test func aPassportOrSTNKGetsItsDateByHand() async throws {
        let store = FakeDocuments()
        let review = model(store)
        review.loadScan(nil, pages: [try page()])
        review.type = .stnk
        #expect(review.hasExpiry)
        #expect(review.expiryMissing)
        #expect(!review.marksMissingExpiry)
        review.type = .simA
        #expect(review.marksMissingExpiry)
        review.type = .passport
        let date = try #require(CalendarDate(year: 2031, month: 3, day: 9))
        review.setExpiry(date)
        #expect(await review.save())
        #expect(try await store.documents().first?.expiry == date)
    }

    /// A date read for one kind of document means something else on another (an STNK's is its tax), so
    /// it's marked when the type changes kind; another SIM class keeps it as it is.
    @Test func aDateFromAnotherKindOfDocumentIsMarked() throws {
        let review = model()
        let sim = ParsedDocument(
            type: .simC, fields: DocumentFields([:]), expiry: CalendarDate(year: 2029, month: 1, day: 4))
        review.loadScan(sim, pages: [try page()])
        review.type = .simA
        #expect(review.expiryNote == nil)
        review.type = .stnk
        #expect(review.expiryNote != nil)
    }

    /// The last page failing is as bad as the first: the document is saved with every page or not at all.
    @Test func aLastPageThatCantBeEncodedSavesNothing() async throws {
        let store = FakeDocuments()
        let review = model(store, encode: { $0.width == 3 ? nil : Data([1]) })
        review.loadScan(Self.ktp, pages: [try page(), try page(width: 3)])
        #expect(await !review.save())
        #expect(review.saveError == .saveFailed)
        #expect(await store.created.isEmpty)
    }

    @Test func aSIMKeepsItsExpiry() async throws {
        let store = FakeDocuments()
        let review = model(store)
        review.loadScan(Self.sim, pages: [try page()])
        #expect(await review.save())
        #expect(try await store.documents().first?.expiry == CalendarDate(year: 2027, month: 1, day: 4))
    }

    /// An expiry read while it was a SIM doesn't follow it when the user makes it a KTP.
    @Test func aSIMChangedToAKTPSavesNoExpiry() async throws {
        let store = FakeDocuments()
        let review = model(store)
        review.loadScan(Self.sim, pages: [try page()])
        review.type = .ktp
        #expect(await review.save())
        #expect(try await store.documents().first?.expiry == nil)
    }

    @Test func aLabelOfOnlySpacesIsNoLabel() async throws {
        let store = FakeDocuments()
        let review = model(store)
        review.loadScan(Self.ktp, pages: [try page()])
        review.label = "   "
        #expect(await review.save())
        #expect(try await store.documents().first?.label == nil)
    }

    // MARK: What Simpan does next

    @Test func aWrongValueIsRefusedBeforeAnythingIsAsked() throws {
        let review = model()
        try loadKTPAndSIM(into: review)
        review.setValue("", for: FieldKey.nik)
        review.setValue("31-02-1990", for: FieldKey.birthDate)
        #expect(review.saveStep() == .refuse(FieldKey.birthDate))
        // Refused, not asked, so the next tap is judged again.
        review.setValue("17-08-1990", for: FieldKey.birthDate)
        #expect(review.saveStep() == .askNIK)
    }

    @Test func anEmptyNIKIsAskedAboutBeforeTheOtherPages() throws {
        let review = model()
        try loadKTPAndSIM(into: review)
        review.setValue("", for: FieldKey.nik)
        #expect(review.saveStep() == .askNIK)
        #expect(review.saveStepWithoutNIK() == .askPages)
    }

    @Test func aPageReadAsAnotherDocumentIsAskedAbout() throws {
        let review = model()
        try loadKTPAndSIM(into: review)
        #expect(review.saveStep() == .askPages)
    }

    @Test func withNothingToAskSimpanSaves() throws {
        let review = model()
        review.loadScan(Self.ktp, pages: [try page()])
        #expect(review.saveStep() == .save)
        review.setValue("", for: FieldKey.nik)
        #expect(review.saveStep() == .askNIK)
        #expect(review.saveStepWithoutNIK() == .save)
    }

    /// A quick second tap, even while one alert closes and the next is about to show, never stacks two.
    @Test func aSecondTapWhileAskingAsksNothing() throws {
        let review = model()
        try loadKTPAndSIM(into: review)
        #expect(review.saveStep() == .askPages)
        #expect(review.saveStep() == nil)
        review.setValue("", for: FieldKey.nik)
        review.alertAnswered()
        #expect(review.saveStep() == .askNIK)
        #expect(review.saveStepWithoutNIK() == .askPages)
        #expect(review.saveStep() == nil)
    }

    /// Isi NIK and Kembali end the questions; the next Simpan starts again from the first.
    @Test func anAnsweredAlertLetsSimpanAskAgain() throws {
        let review = model()
        try loadKTPAndSIM(into: review)
        review.setValue("", for: FieldKey.nik)
        #expect(review.saveStep() == .askNIK)
        review.alertAnswered()
        #expect(review.saveStep() == .askNIK)
        #expect(review.saveStepWithoutNIK() == .askPages)
        review.alertAnswered()
        #expect(review.saveStep() == .askNIK)
    }

    /// Saving ends the questions, so a save that fails lets Simpan be tapped again.
    @Test func aSaveEndsTheQuestions() throws {
        let review = model()
        review.loadScan(Self.ktp, pages: [try page()])
        review.setValue("", for: FieldKey.nik)
        #expect(review.saveStep() == .askNIK)
        #expect(review.saveStepWithoutNIK() == .save)
        #expect(review.saveStep() == .askNIK)
    }

    /// A rescan starts over, even if the alert that was about to follow Simpan saja never showed.
    @Test func aRescanEndsTheQuestions() throws {
        let review = model()
        try loadKTPAndSIM(into: review)
        review.setValue("", for: FieldKey.nik)
        #expect(review.saveStep() == .askNIK)
        #expect(review.saveStepWithoutNIK() == .askPages)
        try loadKTPAndSIM(into: review)
        #expect(review.saveStep() == .askPages)
    }

    /// The pages were already answered, so Simpan goes straight to saving; it never does nothing.
    @Test func aFailedSaveLetsSimpanSaveAgain() async throws {
        let review = model(encode: { _ in nil })
        try loadKTPAndSIM(into: review)
        #expect(review.saveStep() == .askPages)
        #expect(await !review.save())
        #expect(review.saveStep() == .save)
    }

    /// The lock removes Periksa data and cancels its save. While the pages are still being prepared, nothing
    /// is saved: the notice will say the scan was dropped, so the vault mustn't get it after the next unlock.
    @Test func lockDuringSavePreparationSavesNothing() async throws {
        let store = FakeDocuments()
        let review = model(store)
        review.loadScan(Self.ktp, pages: [try page()])
        var reported = 0
        let saving = Task { await review.save(onSaved: { reported += 1 }) }
        // On the main actor, the save hasn't started yet: it's cancelled before its pages are prepared.
        saving.cancel()
        #expect(await !saving.value)
        #expect(await store.created.isEmpty)
        #expect(reported == 0)
        #expect(review.saveError == nil)
    }

    /// Once the vault is writing, a lock lets it finish, and the scan counts as saved, not dropped.
    @Test func lockDuringWriteStillSaves() async throws {
        let store = FakeDocuments()
        await store.gateNextCreate()
        let review = model(store)
        review.loadScan(Self.ktp, pages: [try page()])
        var reported = 0
        let saving = Task { await review.save(onSaved: { reported += 1 }) }
        try #require(await store.waitUntilCreating())
        saving.cancel()
        await store.releaseCreate()
        #expect(await saving.value)
        #expect(await store.created.count == 1)
        #expect(reported == 1)
    }
}
