//
//  FixtureV2Tests.swift
//  VaultCoreTests
//
//  Created by Inez Amanda on 14/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Crypto
import Foundation
import Testing

@testable import VaultCore

/// The committed v2 vault (index schema 2, with labels) must always open. Never replace it, add
/// later versions beside it. Expected values are frozen literals and hashes.
@Suite("v2 fixture")
struct FixtureV2Tests {
    /// <repo>/Fixtures/Synthetic/VaultV2
    static let fixtureURL = FixtureTests.fixtureURL
        .deletingLastPathComponent()
        .appending(path: "VaultV2", directoryHint: .isDirectory)
    static let t0 = ISO8601DateFormatter().date(from: "2026-10-15T00:00:00Z")!

    // MARK: Frozen expectations

    static let ktpFields: [String: String] = ["nik": "0012341708900001", "name": "BUDI CONTOH"]
    static let motherFields: [String: String] = ["nik": "0012345501700002", "name": "SITI CONTOH"]
    static let simFields: [String: String] = ["number": "0000-0000-000002", "name": "BUDI CONTOH"]
    static let npwpFields: [String: String] = ["number": "00.000.000.0-000.001"]
    /// Not plain ASCII, so the encoding of the label is pinned too.
    static let motherLabel = "Ibu & Ayah · Ⅱ"
    static let simExpiry = CalendarDate(year: 2031, month: 2, day: 28)!
    static let simA = DocumentType(rawValue: "sim-a")

    /// SHA-256 of each page as stored by the writer.
    static let ktpPage = "9e105ea9fa7db2bad763c570597d46ed1523a795179d0830998efb628e22d283"
    static let motherPage = "b504e6daea87efd4bd76d5da7ae157792cba5166b3f6d9cf787a0bc4316caab2"
    static let simPage = "cd63666ca539599605fd6d886926219268d0e151166fcb4a960d036017266476"

    // MARK: Opening the fixture

    func openableCopy() async throws -> TestVault {
        let vault = try TestVault(clock: TestClock(Self.t0 + 86_400))
        for item in ["Vault", "AppGroup"] {
            try FileManager.default.copyItem(
                at: Self.fixtureURL.appending(path: item), to: vault.base.appending(path: item))
        }
        let keyText = try String(
            contentsOf: Self.fixtureURL.appending(path: FixtureTests.keyFileName), encoding: .utf8)
        let keyData = try #require(Data(base64Encoded: keyText.trimmingCharacters(in: .whitespacesAndNewlines)))
        await vault.keyStore.setKey(SymmetricKey(data: keyData), for: try vault.header().vaultID)
        return vault
    }

    func hashes(_ store: VaultStore, _ id: DocumentID) async throws -> [String] {
        try await store.pages(of: id).map { SHA256.hash(data: $0.data).map { String(format: "%02x", $0) }.joined() }
    }

    @Test func v2FixtureOpens() async throws {
        let vault = try await openableCopy()
        #expect(try await vault.readIndex(at: vault.indexURL).schemaVersion == 2)
        let store = vault.makeStore()
        let report = try await store.open()
        #expect(!report.createdVault)
        #expect(report.indexSource == .current)
        #expect(!report.recoveredFromPages)
        #expect(report.removedOrphanPages == 0)

        let live = try await store.documents()
        #expect(live.map(\.type) == [.ktp, .ktp, Self.simA])
        #expect(live.map(\.label) == ["Saya", Self.motherLabel, nil])
        try #require(live.count == 3)
        #expect(try await store.fields(of: live[0].id).values == Self.ktpFields)
        #expect(try await store.fields(of: live[1].id).values == Self.motherFields)
        #expect(try await store.fields(of: live[2].id).values == Self.simFields)
        #expect(live[2].expiry == Self.simExpiry)
        #expect(try await hashes(store, live[0].id) == [Self.ktpPage])
        #expect(try await hashes(store, live[1].id) == [Self.motherPage])
        #expect(try await hashes(store, live[2].id) == [Self.simPage])

        let deleted = try await store.recentlyDeleted()
        #expect(deleted.map(\.type) == [.npwp])
        #expect(deleted.map(\.label) == ["Kantor"])
        try #require(deleted.count == 1)
        #expect(try await store.fields(of: deleted[0].id).values == Self.npwpFields)

        // The labels stay out of the projection.
        let projection = try Data(contentsOf: vault.projectionURL)
        for label in ["Saya", Self.motherLabel, "Kantor"] {
            #expect(!projection.contains(bytes: Data(label.utf8)))
        }
    }

    // MARK: Writing the fixture

    /// Writes the fixture, but not over an existing one. Run with:
    /// SIMPANIN_WRITE_FIXTURES=1 swift test --filter writeV2Fixture
    @Test(.enabled(if: ProcessInfo.processInfo.environment["SIMPANIN_WRITE_FIXTURES"] == "1"))
    func writeV2Fixture() async throws {
        guard !FileManager.default.fileExists(atPath: Self.fixtureURL.path) else {
            Issue.record("Fixtures/Synthetic/VaultV2 already exists. The v2 fixture must stay as committed.")
            return
        }
        let clock = TestClock(Self.t0)
        let vault = try TestVault(clock: clock)
        let store = vault.makeStore()
        try await store.open()
        _ = try await store.createDocument(
            type: .ktp, label: "Saya", expiry: nil, pinned: true, fields: DocumentFields(Self.ktpFields),
            pages: [Synthetic.page("fixture-v2-ktp")])
        clock.set(Self.t0 + 60)
        _ = try await store.createDocument(
            type: .ktp, label: Self.motherLabel, expiry: nil, pinned: false,
            fields: DocumentFields(Self.motherFields), pages: [Synthetic.page("fixture-v2-ktp-mother")])
        clock.set(Self.t0 + 120)
        _ = try await store.createDocument(
            type: Self.simA, expiry: Self.simExpiry, pinned: false, fields: DocumentFields(Self.simFields),
            pages: [Synthetic.page("fixture-v2-sim")])
        clock.set(Self.t0 + 180)
        let npwp = try await store.createDocument(
            type: .npwp, label: "Kantor", expiry: nil, pinned: false,
            fields: DocumentFields(Self.npwpFields), pages: [])
        clock.set(Self.t0 + 240)
        try await store.delete(npwp)

        let header = try vault.header()
        let key = try #require(await vault.keyStore.key(for: header.vaultID))
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: Self.fixtureURL, withIntermediateDirectories: true)
        try fileManager.copyItem(at: vault.root, to: Self.fixtureURL.appending(path: "Vault"))
        try fileManager.copyItem(
            at: vault.projectionURL.deletingLastPathComponent(), to: Self.fixtureURL.appending(path: "AppGroup"))
        try (bytes(key).base64EncodedString() + "\n")
            .write(
                to: Self.fixtureURL.appending(path: FixtureTests.keyFileName), atomically: true, encoding: .utf8)
    }
}
