//
//  DuplicateCheckTests.swift
//  SimpaninTests
//
//  Created by Inez Amanda on 27/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import Testing
import VaultCore

@testable import Simpanin

/// Synthetic values only; NIKs start with 00.
@Suite("Duplicate check")
struct DuplicateCheckTests {
    static let nik = "0012341708900001"
    static let otherNIK = "0012341708900002"

    @discardableResult
    func save(_ type: DocumentType, _ values: [String: String], in store: FakeDocuments) async throws -> DocumentID {
        try await store.createDocument(
            type: type, label: nil, expiry: nil, pinned: false, fields: DocumentFields(values), pages: [])
    }

    func ktp(_ nik: String = Self.nik) -> [String: String] { [FieldKey.nik: nik] }
    func sim(_ number: String = Self.nik) -> [String: String] { [FieldKey.simNumber: number] }

    func find(_ type: DocumentType, _ values: [String: String], in store: FakeDocuments) async throws
        -> DuplicateCheck.Found?
    {
        let candidate = try #require(DuplicateCheck.candidate(type: type, values: values))
        return try await DuplicateCheck.find(candidate, in: store)
    }

    @Test func aKTPWithTheSameNIKIsFound() async throws {
        let store = FakeDocuments()
        try await save(.ktp, ktp(), in: store)
        #expect(try await find(.ktp, ktp(), in: store)?.name == .ktp)
        #expect(try await find(.ktp, ktp(Self.otherNIK), in: store) == nil)
    }

    @Test func aSIMWithTheSameNumberAndClassIsFound() async throws {
        let store = FakeDocuments()
        try await save(.simA, sim(), in: store)
        #expect(try await find(.simA, sim(), in: store)?.name == .simA)
    }

    @Test func aDashedOldSIMNumberMatchesItsDigits() async throws {
        let store = FakeDocuments()
        try await save(.simC, sim("0000-0000-000001"), in: store)
        #expect(try await find(.simC, sim("00000000000001"), in: store) != nil)
        #expect(try await find(.simC, sim(" 0000 0000 000001 "), in: store) != nil)
    }

    /// A new SIM's number is the holder's NIK, so a KTP and a SIM of one person share it.
    @Test func aKTPAndASIMWithTheSameNumberNeverMatch() async throws {
        let store = FakeDocuments()
        try await save(.ktp, ktp(), in: store)
        #expect(try await find(.simA, sim(), in: store) == nil)
        let other = FakeDocuments()
        try await save(.simA, sim(), in: other)
        #expect(try await find(.ktp, ktp(), in: other) == nil)
    }

    @Test func twoSIMClassesNeverMatch() async throws {
        let store = FakeDocuments()
        try await save(.simA, sim(), in: store)
        #expect(try await find(.simC, sim(), in: store) == nil)
    }

    @Test func aClasslessSavedSIMMatchesANewSIMA() async throws {
        let store = FakeDocuments()
        try await save(.sim, sim(), in: store)
        #expect(try await find(.simA, sim(), in: store) != nil)
    }

    @Test func aNewClasslessSIMMatchesASavedSIMA() async throws {
        let store = FakeDocuments()
        try await save(.simA, sim(), in: store)
        #expect(try await find(.sim, sim(), in: store) != nil)
    }

    @Test func theWarningSaysSIMWhenEitherClassIsMissing() async throws {
        let classlessSaved = FakeDocuments()
        try await save(.sim, sim(), in: classlessSaved)
        #expect(try await find(.simA, sim(), in: classlessSaved)?.name == .sim)
        let classedSaved = FakeDocuments()
        try await save(.simA, sim(), in: classedSaved)
        #expect(try await find(.sim, sim(), in: classedSaved)?.name == .sim)
    }

    /// A classless match seen first doesn't hide a saved SIM of the very same class.
    @Test func anExactClassMatchIsNamed() async throws {
        let store = FakeDocuments()
        try await save(.sim, sim(), in: store)
        try await save(.simA, sim(), in: store)
        #expect(try await find(.simA, sim(), in: store)?.name == .simA)
    }

    @Test func anEmptyNumberIsNeverChecked() {
        #expect(DuplicateCheck.candidate(type: .ktp, values: [:]) == nil)
        #expect(DuplicateCheck.candidate(type: .ktp, values: ktp("  ")) == nil)
        #expect(DuplicateCheck.candidate(type: .simA, values: [:]) == nil)
    }

    @Test func aNumberWithoutDigitsIsNeverChecked() {
        #expect(DuplicateCheck.candidate(type: .simA, values: sim("--")) == nil)
        #expect(DuplicateCheck.candidate(type: .simA, values: sim(" - ")) == nil)
    }

    @Test func aSavedDocumentWithoutANumberNeverMatches() async throws {
        let store = FakeDocuments()
        try await save(.simA, [:], in: store)
        try await save(.simA, sim("--"), in: store)
        try await save(.ktp, [FieldKey.name: "BUDI CONTOH"], in: store)
        #expect(try await find(.simA, sim(), in: store) == nil)
        #expect(try await find(.ktp, ktp(), in: store) == nil)
    }

    @Test func aDocumentInBaruDihapusIsntCounted() async throws {
        let store = FakeDocuments()
        let id = try await save(.ktp, ktp(), in: store)
        try await store.delete(id)
        #expect(try await find(.ktp, ktp(), in: store) == nil)
    }

    @Test func anUnreadableDocumentIsSkipped() async throws {
        let store = FakeDocuments()
        await store.setUnreadable(try await save(.ktp, ktp(), in: store))
        #expect(try await find(.ktp, ktp(), in: store) == nil)
        try await save(.ktp, ktp(), in: store)
        #expect(try await find(.ktp, ktp(), in: store) != nil)
    }

    @Test func aFailedListLetsTheSaveGoAhead() async throws {
        let store = FakeDocuments()
        try await save(.ktp, ktp(), in: store)
        await store.setLoadFailure(.corruptFile)
        #expect(try await find(.ktp, ktp(), in: store) == nil)
    }

    @Test func aLockStopsTheCheck() async throws {
        let store = FakeDocuments()
        try await save(.ktp, ktp(), in: store)
        await store.lock()
        await #expect(throws: VaultError.locked) { try await find(.ktp, ktp(), in: store) }
    }

    @Test func aTypeWithoutFieldsReadsNothing() {
        for type in [DocumentType.passport, .stnk, .kk, .npwp, .bpjs, .other] {
            #expect(DuplicateCheck.candidate(type: type, values: ktp()) == nil)
        }
    }

    /// One match is enough for the warning, so the check stops there.
    @Test func severalMatchesShowOneWarning() async throws {
        let store = FakeDocuments()
        try await save(.ktp, ktp(), in: store)
        try await save(.ktp, ktp(), in: store)
        #expect(try await find(.ktp, ktp(), in: store)?.name == .ktp)
        #expect(await store.fieldReads.count == 1)
    }

    @Test func onlyDocumentsThatCanMatchAreDecrypted() async throws {
        let store = FakeDocuments()
        try await save(.ktp, ktp(), in: store)
        let classless = try await save(.sim, sim(Self.otherNIK), in: store)
        try await save(.simC, sim(), in: store)
        try await save(.passport, ktp(), in: store)
        let simA = try await save(.simA, sim(Self.otherNIK), in: store)
        #expect(try await find(.simA, sim(), in: store) == nil)
        #expect(await store.fieldReads == [classless, simA])
    }
}
