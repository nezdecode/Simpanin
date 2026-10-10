import Crypto
import Foundation
import Testing

@testable import VaultCore

/// Crash after each step of the write order, reopen, and find the last good state.
@Suite("Crash simulation")
struct CrashTests {
    enum Operation: String, CaseIterable, Sendable {
        case create, edit, addPage, replacePage, softDelete, restore, deletePermanently
    }

    struct Baseline {
        let vault: TestVault
        let ktp: DocumentID  // live KTP, two pages
        let sim: DocumentID  // SIM in Recently deleted, one page
    }

    func makeBaseline() async throws -> Baseline {
        let start = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
        let vault = try TestVault(clock: TestClock(start))
        let store = vault.makeStore()
        try await store.open()
        let ktp = try await store.createDocument(
            type: .ktp, expiry: nil, pinned: false, fields: Synthetic.ktpFields,
            pages: [Synthetic.page("a1"), Synthetic.page("a2")])
        let sim = try await store.createDocument(
            type: .sim, expiry: Synthetic.simExpiry, pinned: false,
            fields: Synthetic.simFields, pages: [Synthetic.page("b1")])
        try await store.delete(sim)
        return Baseline(vault: vault, ktp: ktp, sim: sim)
    }

    func perform(_ operation: Operation, on store: VaultStore, _ base: Baseline) async throws {
        switch operation {
        case .create:
            _ = try await store.createDocument(
                type: .passport, expiry: Synthetic.simExpiry, pinned: false,
                fields: DocumentFields(["number": "X0000001"]),
                pages: [Synthetic.page("n1"), Synthetic.page("n2")])
        case .edit:
            try await store.editDocument(
                base.ktp, type: .ktp, expiry: nil, pinned: true,
                fields: DocumentFields(["nik": Synthetic.nik, "name": "ANI CONTOH"]))
        case .addPage:
            _ = try await store.addPage(Synthetic.page("a3"), to: base.ktp)
        case .replacePage:
            let first = try await store.document(base.ktp).pageIDs[0]
            _ = try await store.replacePage(first, of: base.ktp, with: Synthetic.page("a1-rescan"))
        case .softDelete:
            try await store.delete(base.ktp)
        case .restore:
            try await store.restore(base.sim)
        case .deletePermanently:
            try await store.deletePermanently(base.ktp)
        }
    }

    /// Every page file is referenced by the index, and the projection matches it.
    func expectConsistent(_ vault: TestVault, _ store: VaultStore, _ label: String) async throws {
        let docs = try await store.documents() + store.recentlyDeleted()
        let referenced = Set(docs.flatMap(\.pageIDs).map { "\($0.string).enc" })
        let files = Set(try vault.pageFiles().map(\.lastPathComponent))
        #expect(files == referenced, "page files after \(label)")
        let live = try await store.documents().map(\.id)
        #expect(Set(try vault.projection().documents.map(\.id)) == Set(live), "projection after \(label)")
    }

    @Test(arguments: Operation.allCases)
    func crashAfterEachWriteStep(_ operation: Operation) async throws {
        let base = try await makeBaseline()
        let before = try await base.vault.makeStore().snapshotAfterOpen()

        // A clean run tells us the steps and the state after the operation.
        let dry = try await base.vault.copy()
        let recorder = CrashSwitch()
        let dryStore = dry.makeStore(crash: recorder)
        try await dryStore.open()
        recorder.arm()
        try await perform(operation, on: dryStore, base)
        let after = try await dryStore.snapshot()
        let steps = recorder.steps
        // The design doc's write order; a purge writes the index twice.
        let indexWrite: [WriteStep] = [.indexMovedToPrevious, .indexWritten]
        let indexWrites = operation == .deletePermanently ? indexWrite + indexWrite : indexWrite
        #expect(steps == [.pagesWritten] + indexWrites + [.obsoletePagesDeleted, .projectionWritten])
        #expect(before != after)

        for crashStep in 1...steps.count {
            let label = "\(operation.rawValue), crash after step \(crashStep) (\(steps[crashStep - 1]))"
            let run = try await base.vault.copy()
            let crash = CrashSwitch(crashAt: crashStep)
            let store = run.makeStore(crash: crash)
            try await store.open()
            crash.arm()
            await #expect(throws: SimulatedCrash.self, "\(label)") { try await perform(operation, on: store, base) }

            run.clock.advance(by: 3600)  // old enough for orphan cleanup
            let reopened = run.makeStore()
            let report = try await reopened.open()
            let expected = steps.prefix(crashStep).contains(.indexWritten) ? after : before
            #expect(try await reopened.snapshot() == expected, "\(label)")
            // A crash right after index.enc was moved aside: the newest change may be lost.
            #expect(report.newestChangeMayBeLost == (steps[crashStep - 1] == .indexMovedToPrevious), "\(label)")
            #expect(!report.recoveredFromPages, "\(label)")
            try await expectConsistent(run, reopened, label)
        }
    }

    @Test func crashDuringPurgeOnOpen() async throws {
        let base = try await makeBaseline()
        let purgeTime = base.vault.clock.now + 30 * 86_400 + 1
        let sealedB = try #require(
            try await base.vault.readIndex(at: base.vault.indexURL)
                .documents.first { $0.id == base.sim }?.sealedKey)

        let dry = try await base.vault.copy(clock: TestClock(purgeTime))
        let recorder = CrashSwitch()
        recorder.arm()
        let dryStore = dry.makeStore(crash: recorder)
        #expect(try await dryStore.open().purgedDocuments == 1)
        let after = try await dryStore.snapshot()
        let steps = recorder.steps
        #expect(steps.filter { $0 == .indexWritten }.count >= 2)

        for crashStep in 1...steps.count {
            let label = "purge on open, crash after step \(crashStep) (\(steps[crashStep - 1]))"
            let run = try await base.vault.copy(clock: TestClock(purgeTime))
            let crash = CrashSwitch(crashAt: crashStep)
            crash.arm()
            await #expect(throws: SimulatedCrash.self, "\(label)") { try await run.makeStore(crash: crash).open() }

            run.clock.advance(by: 3600)
            let reopened = run.makeStore()
            let report = try await reopened.open()
            #expect(try await reopened.snapshot() == after, "\(label)")
            #expect(report.newestChangeMayBeLost == (steps[crashStep - 1] == .indexMovedToPrevious), "\(label)")
            try await expectConsistent(run, reopened, label)
            // Whatever step the crash hit, no index file keeps the SIM's sealed key once reopened.
            for url in [run.indexURL, run.previousIndexURL] where FileManager.default.fileExists(atPath: url.path) {
                let index = try await run.readIndex(at: url)
                #expect(!index.documents.contains { $0.sealedKey == sealedB }, "\(label): \(url.lastPathComponent)")
            }
        }
    }
}

extension VaultStore {
    func snapshotAfterOpen() async throws -> [DocumentSnapshot] {
        try await open()
        return try snapshot()
    }
}
