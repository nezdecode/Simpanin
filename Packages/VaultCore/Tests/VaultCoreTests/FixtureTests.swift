import Crypto
import Foundation
import Testing

@testable import VaultCore

/// Required test 6: a committed v1 vault, built from synthetic data, still opens.
/// Keep this fixture for every later format version; add a new one beside it, never replace it.
///
/// Expected values are frozen here as literals and SHA-256 hashes, independent of the
/// `Synthetic` helpers, so changing a helper can never make this test pass against a
/// different vault.
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

    // MARK: Frozen expectations

    static let ktpFields: [String: String] = ["nik": "0012341708900001", "name": "BUDI CONTOH"]
    static let simFields: [String: String] = ["number": "0000-0000-000001", "name": "BUDI CONTOH"]
    static let npwpFields: [String: String] = [
        "number": "00.000.000.0-000.000",
        "name": "RENÉ CONTOH",
        "address": "Jl. Perintis Kemerdekaan Ⅳ, Makassar",
    ]
    static let visaFields: [String: String] = ["number": "V0000001"]
    static let passportFields: [String: String] = ["number": "X0000000", "name": "BUDI CONTOH"]

    /// SHA-256 of each page as stored by the writer.
    static let ktpFrontRescan = "d0d682c7a6aeaa6d3fb38ffc2d8b49860f95decc53fede59fddddb829f66a13d"
    static let ktpBack = "5589c6fbd9b13a1ee4c2e3c922f1f4cd14873a77c16a3def9cb5e6c61c7741b7"
    static let simPage = "89c7843935b013dc548ff99cd57f6c9437c9f81d6a3fef36957712e19ae70387"
    static let visaPage = "6b8d1bd48656a0e2e20d268a26331cf3c1fbec81ee74e46ebed252f1ca1a8ee3"
    static let passportPage = "263510e7f6e1f7be8b3984252a44870bf2add90521bc98b2f391ffb2abb5e601"

    static let simExpiry = CalendarDate(year: 2030, month: 8, day: 17)!
    static let visaExpiry = CalendarDate(year: 2027, month: 3, day: 1)!
    static let passportExpiry = CalendarDate(year: 2031, month: 1, day: 31)!
    static let visa = DocumentType(rawValue: "visa")  // not a type this build knows

    // MARK: Opening the fixture

    /// A copy of the fixture in a temporary folder, with its test key loaded.
    func openableCopy() async throws -> TestVault {
        let vault = try TestVault(clock: TestClock(Self.t0 + 86_400))
        for item in ["Vault", "AppGroup"] {
            try FileManager.default.copyItem(
                at: Self.fixtureURL.appending(path: item),
                to: vault.base.appending(path: item))
        }
        let keyText = try String(contentsOf: Self.fixtureURL.appending(path: Self.keyFileName), encoding: .utf8)
        let keyData = try #require(Data(base64Encoded: keyText.trimmingCharacters(in: .whitespacesAndNewlines)))
        await vault.keyStore.setKey(SymmetricKey(data: keyData), for: try vault.header().vaultId)
        return vault
    }

    func hashes(_ store: VaultStore, _ id: DocumentID) async throws -> [String] {
        try await store.pages(of: id).map { SHA256.hash(data: $0.data).map { String(format: "%02x", $0) }.joined() }
    }

    func expectLiveDocuments(_ store: VaultStore, _ live: [Document]) async throws {
        #expect(live.map(\.type) == [.ktp, .sim, .npwp, Self.visa])
        try #require(live.count == 4)
        let ktp = live[0]
        let sim = live[1]
        let npwp = live[2]
        let visa = live[3]

        #expect(ktp.pinned)
        #expect(ktp.expiry == nil)
        #expect(ktp.createdAt == Self.t0)
        #expect(ktp.updatedAt == Self.t0 + 180)  // the front page was replaced
        #expect(try await store.fields(of: ktp.id).values == Self.ktpFields)
        #expect(try await hashes(store, ktp.id) == [Self.ktpFrontRescan, Self.ktpBack])

        #expect(!sim.pinned)
        #expect(sim.expiry == Self.simExpiry)
        #expect(sim.createdAt == Self.t0 + 60)
        #expect(sim.updatedAt == Self.t0 + 120)
        #expect(try await store.fields(of: sim.id).values == Self.simFields)
        #expect(try await hashes(store, sim.id) == [Self.simPage])

        #expect(npwp.pageIDs.isEmpty)
        #expect(npwp.createdAt == Self.t0 + 240)
        #expect(try await store.fields(of: npwp.id).values == Self.npwpFields)

        #expect(visa.expiry == Self.visaExpiry)
        #expect(visa.createdAt == Self.t0 + 300)
        #expect(try await store.fields(of: visa.id).values == Self.visaFields)
        #expect(try await hashes(store, visa.id) == [Self.visaPage])
    }

    @Test func v1FixtureOpens() async throws {
        let vault = try await openableCopy()
        let header = try vault.header()
        #expect(header.formatVersion == 1)
        #expect(header.keySlots.map(\.kind) == [.device])
        #expect(header.keySlots.first?.createdAt == Self.t0)
        #expect(try await vault.readIndex(at: vault.indexURL).generation == 9)

        let store = vault.makeStore()
        let report = try await store.open()
        #expect(!report.createdVault)
        #expect(report.indexSource == .current)
        #expect(!report.newestChangeMayBeLost)
        #expect(!report.recoveredFromPages)
        #expect(report.purgedDocuments == 0)
        #expect(report.removedOrphanPages == 0)
        #expect(report.unreadablePages == 0)
        #expect(await vault.keyStore.createCount == 0)

        let live = try await store.documents()
        try await expectLiveDocuments(store, live)

        let deleted = try await store.recentlyDeleted()
        #expect(deleted.map(\.type) == [.passport])
        try #require(deleted.count == 1)
        #expect(deleted.first?.deletedAt == Self.t0 + 420)
        #expect(deleted.first?.expiry == Self.passportExpiry)
        #expect(deleted.first?.createdAt == Self.t0 + 360)
        #expect(try await store.fields(of: deleted[0].id).values == Self.passportFields)
        #expect(try await hashes(store, deleted[0].id) == [Self.passportPage])

        #expect(
            try vault.projection().documents == [
                ProjectionEntry(id: live[0].id, type: .ktp, expiry: nil, reminderOffsets: [60, 30, 7]),
                ProjectionEntry(id: live[1].id, type: .sim, expiry: Self.simExpiry, reminderOffsets: [60, 30, 7]),
                ProjectionEntry(id: live[2].id, type: .npwp, expiry: nil, reminderOffsets: [60, 30, 7]),
                ProjectionEntry(
                    id: live[3].id, type: Self.visa, expiry: Self.visaExpiry, reminderOffsets: [60, 30, 7]),
            ])
    }

    @Test func v1FixtureOpensFromThePreviousIndex() async throws {
        // F4: without index.enc, generation 8 from index.prev.enc: the passport is not deleted yet.
        let vault = try await openableCopy()
        try FileManager.default.removeItem(at: vault.indexURL)
        #expect(try await vault.readIndex(at: vault.previousIndexURL).generation == 8)

        let store = vault.makeStore()
        let report = try await store.open()
        #expect(report.indexSource == .previous)
        #expect(report.newestChangeMayBeLost)
        #expect(report.removedOrphanPages == 0)
        #expect(report.unreadablePages == 0)

        let live = try await store.documents()
        #expect(live.map(\.type) == [.ktp, .sim, .npwp, Self.visa, .passport])
        try #require(live.count == 5)
        try await expectLiveDocuments(store, Array(live.prefix(4)))
        #expect(live[4].deletedAt == nil)
        #expect(try await store.fields(of: live[4].id).values == Self.passportFields)
        #expect(try await store.recentlyDeleted().isEmpty)
    }

    // MARK: Writing the fixture

    /// Writes the fixture. Refuses if it already exists: the v1 fixture is replaced only by
    /// deleting it by hand, on purpose. Run with:
    /// SIMPANIN_WRITE_FIXTURES=1 swift test --filter writeV1Fixture
    @Test(.enabled(if: ProcessInfo.processInfo.environment["SIMPANIN_WRITE_FIXTURES"] == "1"))
    // swiftlint:disable:next function_body_length - the nine generations read best as one sequence
    func writeV1Fixture() async throws {
        guard !FileManager.default.fileExists(atPath: Self.fixtureURL.path) else {
            Issue.record(
                """
                Fixtures/Synthetic/VaultV1 already exists. The v1 fixture must stay as committed. \
                To replace it on purpose, delete the folder by hand and run this again.
                """)
            return
        }
        let clock = TestClock(Self.t0)
        let vault = try TestVault(clock: clock)
        let store = vault.makeStore()
        try await store.open()  // generation 1
        let ktp = try await store.createDocument(
            type: .ktp, expiry: nil, pinned: true,
            fields: DocumentFields(Self.ktpFields),
            pages: [
                Synthetic.page("fixture-ktp-front"),
                Synthetic.page("fixture-ktp-back"),
            ])  // 2
        clock.set(Self.t0 + 60)
        let sim = try await store.createDocument(
            type: .sim, expiry: nil, pinned: true, fields: DocumentFields(),
            pages: [Synthetic.page("fixture-sim")])  // 3
        clock.set(Self.t0 + 120)
        try await store.editDocument(
            sim, type: .sim, expiry: Self.simExpiry, pinned: false,
            fields: DocumentFields(Self.simFields))  // 4
        clock.set(Self.t0 + 180)
        _ = try await store.replacePage(
            try await store.document(ktp).pageIDs[0], of: ktp,
            with: Synthetic.page("fixture-ktp-front-rescan"))  // 5
        clock.set(Self.t0 + 240)
        _ = try await store.createDocument(
            type: .npwp, expiry: nil, pinned: false,
            fields: DocumentFields(Self.npwpFields), pages: [])  // 6
        clock.set(Self.t0 + 300)
        _ = try await store.createDocument(
            type: Self.visa, expiry: Self.visaExpiry, pinned: false,
            fields: DocumentFields(Self.visaFields),
            pages: [Synthetic.page("fixture-visa")])  // 7
        clock.set(Self.t0 + 360)
        let passport = try await store.createDocument(
            type: .passport, expiry: Self.passportExpiry, pinned: false,
            fields: DocumentFields(Self.passportFields),
            pages: [Synthetic.page("fixture-passport")])  // 8
        clock.set(Self.t0 + 420)
        try await store.delete(passport)  // 9

        let header = try vault.header()
        let key = try #require(await vault.keyStore.key(for: header.vaultId))
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: Self.fixtureURL, withIntermediateDirectories: true)
        try fileManager.copyItem(at: vault.root, to: Self.fixtureURL.appending(path: "Vault"))
        try fileManager.copyItem(
            at: vault.projectionURL.deletingLastPathComponent(), to: Self.fixtureURL.appending(path: "AppGroup"))
        try (bytes(key).base64EncodedString() + "\n")
            .write(to: Self.fixtureURL.appending(path: Self.keyFileName), atomically: true, encoding: .utf8)
    }
}
