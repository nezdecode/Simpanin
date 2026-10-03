import Crypto
import Foundation
import Testing
@testable import VaultCore

/// Required test 6: a committed v1 vault, built from synthetic data, still opens.
/// Keep this fixture for every later format version; add a new one beside it, never replace it.
@Suite("v1 fixture")
struct FixtureTests {
    /// <repo>/Fixtures/Synthetic/VaultV1
    static let fixtureURL = URL(filePath: #filePath)
        .deletingLastPathComponent()  // VaultCoreTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // VaultCore
        .deletingLastPathComponent()  // Packages
        .deletingLastPathComponent()  // repo root
        .appending(path: "Fixtures/Synthetic/VaultV1", directoryHint: .isDirectory)

    /// Test-only vault key for the fixture. It protects synthetic data only.
    static let keyFileName = "test-vault-key.base64"
    static let t0 = ISO8601DateFormatter().date(from: "2026-10-04T00:00:00Z")!

    static let passportFields = DocumentFields(["number": "X0000000", "name": Synthetic.name])
    static let passportExpiry = CalendarDate(year: 2031, month: 1, day: 31)!

    @Test func v1FixtureOpens() async throws {
        let vault = try TestVault(clock: TestClock(Self.t0 + 86_400))
        for item in ["Vault", "AppGroup"] {
            try FileManager.default.copyItem(at: Self.fixtureURL.appending(path: item),
                                             to: vault.base.appending(path: item))
        }
        let keyText = try String(contentsOf: Self.fixtureURL.appending(path: Self.keyFileName), encoding: .utf8)
        let keyData = try #require(Data(base64Encoded: keyText.trimmingCharacters(in: .whitespacesAndNewlines)))
        let header = try vault.header()
        #expect(header.formatVersion == 1)
        #expect(header.keySlots.map(\.kind) == [.device])
        await vault.keyStore.setKey(SymmetricKey(data: keyData), for: header.vaultId)
        #expect(try await vault.readIndex(at: vault.indexURL).generation == 6)

        let store = vault.makeStore()
        let report = try await store.open()
        #expect(!report.createdVault)
        #expect(report.indexSource == .current)
        #expect(report.purgedDocuments == 0)
        #expect(report.removedOrphanPages == 0)
        #expect(report.unreadablePages == 0)
        #expect(await vault.keyStore.createCount == 0)

        let live = try await store.documents()
        #expect(live.map(\.type) == [.ktp, .sim])
        let ktp = live[0], sim = live[1]
        #expect(ktp.pinned)
        #expect(ktp.expiry == nil)
        #expect(ktp.createdAt == Self.t0)
        #expect(try await store.fields(of: ktp.id) == Synthetic.ktpFields)
        #expect(try await store.pages(of: ktp.id).map(\.data)
            == [Synthetic.page("fixture-ktp-front"), Synthetic.page("fixture-ktp-back")])

        #expect(sim.expiry == Synthetic.simExpiry)
        #expect(sim.createdAt == Self.t0 + 60)
        #expect(sim.updatedAt == Self.t0 + 120)
        #expect(try await store.fields(of: sim.id) == Synthetic.simFields)
        #expect(try await store.pages(of: sim.id).map(\.data) == [Synthetic.page("fixture-sim")])

        let deleted = try await store.recentlyDeleted()
        #expect(deleted.map(\.type) == [.passport])
        #expect(deleted.first?.deletedAt == Self.t0 + 180)
        #expect(deleted.first?.expiry == Self.passportExpiry)
        #expect(try await store.fields(of: deleted[0].id) == Self.passportFields)
        #expect(try await store.pages(of: deleted[0].id).map(\.data) == [Synthetic.page("fixture-passport")])

        #expect(try vault.projection().documents == [
            ProjectionEntry(id: ktp.id, type: .ktp, expiry: nil, reminderOffsets: [60, 30, 7]),
            ProjectionEntry(id: sim.id, type: .sim, expiry: Synthetic.simExpiry, reminderOffsets: [60, 30, 7]),
        ])
    }

    /// Writes the fixture. Run once, on purpose, with:
    /// SIMPANIN_WRITE_FIXTURES=1 swift test --filter writeV1Fixture
    @Test(.enabled(if: ProcessInfo.processInfo.environment["SIMPANIN_WRITE_FIXTURES"] == "1"))
    func writeV1Fixture() async throws {
        let clock = TestClock(Self.t0)
        let vault = try TestVault(clock: clock)
        let store = vault.makeStore()
        try await store.open()                                                       // generation 1
        _ = try await store.createDocument(type: .ktp, expiry: nil, pinned: true, fields: Synthetic.ktpFields,
                                           pages: [Synthetic.page("fixture-ktp-front"),
                                                   Synthetic.page("fixture-ktp-back")])  // 2
        clock.set(Self.t0 + 60)
        let sim = try await store.createDocument(type: .sim, expiry: nil, pinned: true, fields: DocumentFields(),
                                                 pages: [Synthetic.page("fixture-sim")])  // 3
        clock.set(Self.t0 + 120)
        try await store.editDocument(sim, type: .sim, expiry: Synthetic.simExpiry, pinned: false,
                                     fields: Synthetic.simFields)                         // 4
        clock.set(Self.t0 + 180)
        let passport = try await store.createDocument(type: .passport, expiry: Self.passportExpiry, pinned: false,
                                                      fields: Self.passportFields,
                                                      pages: [Synthetic.page("fixture-passport")])  // 5
        try await store.delete(passport)                                             // 6

        let header = try vault.header()
        let key = try #require(await vault.keyStore.key(for: header.vaultId))
        let fm = FileManager.default
        try? fm.removeItem(at: Self.fixtureURL)
        try fm.createDirectory(at: Self.fixtureURL, withIntermediateDirectories: true)
        try fm.copyItem(at: vault.root, to: Self.fixtureURL.appending(path: "Vault"))
        try fm.copyItem(at: vault.projectionURL.deletingLastPathComponent(), to: Self.fixtureURL.appending(path: "AppGroup"))
        try (bytes(key).base64EncodedString() + "\n")
            .write(to: Self.fixtureURL.appending(path: Self.keyFileName), atomically: true, encoding: .utf8)
    }
}
