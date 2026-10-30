//
//  UITestSetup.swift
//  Simpanin
//
//  Created by Inez Amanda on 14/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

#if DEBUG
    import Foundation
    import CoreGraphics
    import VaultCore

    /// Launch arguments the UI tests use. `-SimpaninUITest` starts on a fresh throwaway vault
    /// with an in-memory key. `-SimpaninUITestOpenError <case>` makes opening fail, so a test
    /// lands on a recovery screen; `-SimpaninUITestPasscode notSet` acts as if there's no passcode.
    /// `-SimpaninUITestBrokenOldVault` puts a folder VaultCore can't read into Data lama.
    /// `-SimpaninUITestScan` makes "+" skip the camera, which the simulator lacks, and read a synthetic KTP;
    /// `-SimpaninUITestScanKTPAndSIM` does the same with two pages, a synthetic KTP and SIM A.
    /// `-SimpaninUITestSlowRead` makes each synthetic page take two seconds to read.
    nonisolated enum UITestSetup {
        static var isActive: Bool { ProcessInfo.processInfo.arguments.contains("-SimpaninUITest") }

        private static func value(after flag: String) -> String? {
            let arguments = ProcessInfo.processInfo.arguments
            guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
            return arguments[index + 1]
        }

        /// The error, and how many opens fail with it. "Any other status" needs two failures in
        /// a row before its screen shows.
        static var openFailure: (error: VaultError, times: Int)? {
            switch value(after: "-SimpaninUITestOpenError") {
            case "keyMissing": (.vaultKeyMissing, 1)
            case "vaultUnreadable": (.vaultUnreadable, 1)
            case "phoneLocked": (.vaultKeyUnavailable(status: -25308), 1)
            case "otherStatus": (.vaultKeyUnavailable(status: nil), 2)
            case "newerVersion": (.unsupportedVersion, 1)
            case "storageFull": (.storageFull, 1)
            default: nil
            }
        }

        private static let settingsName = "SimpaninUITests"

        /// UI tests keep their settings apart from the app's, so a test run never changes the
        /// owner's own choices, even on a phone.
        /// Computed rather than stored: UserDefaults isn't Sendable, and every instance with this
        /// name reads and writes the same store.
        static var settings: UserDefaults { UserDefaults(suiteName: settingsName) ?? .standard }

        /// Every UI test starts from the default settings, whatever an earlier run chose.
        static func resetSettings() {
            settings.removePersistentDomain(forName: settingsName)
        }

        /// A synthetic folder with an unreadable vault.json, dated 2 Oct 2026.
        static func addBrokenOldVault(to quarantine: URL) {
            guard ProcessInfo.processInfo.arguments.contains("-SimpaninUITestBrokenOldVault") else { return }
            let folder = quarantine.appending(path: "20261002-031500", directoryHint: .isDirectory)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try? Data("not a vault".utf8).write(to: folder.appending(path: VaultStore.headerFileName))
        }

        /// The store the document list reads. `-SimpaninUITestLoadError <n>` fails its first n loads;
        /// `-SimpaninUITestDeleteError` fails every Hapus.
        static func documentStore(for vault: AppVault) -> any DocumentStoring & PageReading {
            let count = value(after: "-SimpaninUITestLoadError").flatMap(Int.init)
            let failsDeletes = ProcessInfo.processInfo.arguments.contains("-SimpaninUITestDeleteError")
            guard count != nil || failsDeletes else { return vault.store }
            return ScriptedDocuments(store: vault.store, failingLoads: count ?? 0, failsDeletes: failsDeletes)
        }

        /// `-SimpaninUITestCaptureAfterScan`: once the synthetic scan is read, act for a few seconds as if
        /// the screen were being recorded, so a test can check the cover sits above the scan flow.
        static var capturesAfterScan: Bool {
            isActive && ProcessInfo.processInfo.arguments.contains("-SimpaninUITestCaptureAfterScan")
        }

        /// `-SimpaninUITestExpiringSamples`: samples expire within days, so the banner shows.
        static var expiringSamples: Bool {
            isActive && ProcessInfo.processInfo.arguments.contains("-SimpaninUITestExpiringSamples")
        }

        static var scansSynthetically: Bool { scansKTP || scansKTPAndSIM }

        /// So a test can act on Periksa data while a rescan is still being read.
        static var readsSlowly: Bool {
            isActive && ProcessInfo.processInfo.arguments.contains("-SimpaninUITestSlowRead")
        }

        private static var scansKTP: Bool {
            isActive && ProcessInfo.processInfo.arguments.contains("-SimpaninUITestScan")
        }

        private static var scansKTPAndSIM: Bool {
            isActive && ProcessInfo.processInfo.arguments.contains("-SimpaninUITestScanKTPAndSIM")
        }

        /// Blank pages; the recognizer below tells them apart by their width alone, so a rescan reads the same.
        static var syntheticPages: [CGImage] {
            (scansKTPAndSIM ? [8, 9] : [8]).compactMap(blankPage)
        }

        private static func blankPage(width: Int) -> CGImage? {
            CGContext(
                data: nil, width: width, height: 8, bitsPerComponent: 8, bytesPerRow: 4 * width,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )?.makeImage()
        }

        /// A synthetic KTP whose name is marked, so the review screen shows Periksa lagi, and on a page 9 wide
        /// a synthetic SIM A with the same NIK as its number.
        struct SyntheticRecognizer: TextRecognizer {
            func lines(in page: CGImage) async throws -> [String] {
                if UITestSetup.readsSlowly { try await Task.sleep(for: .seconds(2)) }
                return page.width == 9 ? Self.sim : Self.ktp
            }

            private static let ktp = [
                "PROVINSI DKI JAKARTA", "NIK : 0012341708900001", "Nama : BUDI C0NTOH",
                "Tempat/Tgl Lahir : JAKARTA, 17-08-1990", "Jenis Kelamin : LAKI-LAKI",
            ]

            private static let sim = [
                "INDONESIA", "DRIVING LICENSE", "SURAT IZIN MENGEMUDI", "0012341708900001", "A",
                "Mobil Penumpang Pribadi/", "Passenger Car/ Personal Goods", "Nama/Name", "BUDI CONTOH",
                "Tempat, Tgl Lahir/Place, Date of Birth", "JAKARTA, 17-08-1990", "Gol Darah/Blood Type",
                "Jenis Kelamin/Sex", "O", "PRIA", "Alamat/Address", "JL. CONTOH NO. 1", "Pekerjaan/Occupation",
                "KARYAWAN", "Diterbitkan Oleh/Issued by", "POLRES CONTOH", "29-07-2029",
            ]
        }

        static var passcode: PasscodeState {
            value(after: "-SimpaninUITestPasscode") == "notSet" ? .notSet : .set
        }

        @MainActor
        static func lockController(for vault: AppVault) -> LockController {
            let opener: any VaultOpening =
                openFailure.map { ScriptedOpening(store: vault.store, failure: $0.error, times: $0.times) }
                ?? vault.store
            let passcode = passcode
            // The same launch path as the app: the lock starts from the stored choice.
            return LockController(
                vault: opener, autoLock: AutoLock.stored(in: settings), settings: settings, passcode: { passcode },
                vaultExists: { VaultStore.vaultExists(in: vault.locations.root) },
                protectedDataAvailable: { true })
        }
    }

    /// Fails the first loads of the document list, so a test sees the "couldn't load" state and
    /// then "Coba lagi" working, and can fail every delete. Everything else goes to the real (throwaway) store.
    actor ScriptedDocuments {
        private let store: VaultStore
        private var failingLoads: Int
        private let failsDeletes: Bool

        init(store: VaultStore, failingLoads: Int, failsDeletes: Bool = false) {
            self.store = store
            self.failingLoads = failingLoads
            self.failsDeletes = failsDeletes
        }

        func documents() async throws -> [Document] {
            if failingLoads > 0 {
                failingLoads -= 1
                throw VaultError.locked
            }
            return try await store.documents()
        }

        func recentlyDeleted() async throws -> [Document] { try await store.recentlyDeleted() }
        func fields(of id: DocumentID) async throws -> DocumentFields { try await store.fields(of: id) }

        // swiftlint:disable:next function_parameter_count - mirrors VaultStore.createDocument
        func createDocument(
            type: DocumentType, label: String?, expiry: CalendarDate?, pinned: Bool, fields: DocumentFields,
            pages: [Data]
        ) async throws -> DocumentID {
            try await store.createDocument(
                type: type, label: label, expiry: expiry, pinned: pinned, fields: fields, pages: pages)
        }

        func delete(_ id: DocumentID) async throws {
            if failsDeletes { throw VaultError.fileUnavailable }
            try await store.delete(id)
        }
        func restore(_ id: DocumentID) async throws { try await store.restore(id) }
        func pageData(_ pageID: PageID, of id: DocumentID) async throws -> Data {
            try await store.pageData(pageID, of: id)
        }
    }

    // In an extension: declared on the actor, a conformance to a nonisolated protocol makes Swift 6.4 mark the
    // actor's init nonisolated, and reject it, when a file using the actor is type-checked first.
    extension ScriptedDocuments: DocumentStoring, PageReading {}

    /// Fails the first opens with a chosen error, then opens the real (throwaway) store.
    actor ScriptedOpening {
        private let store: VaultStore
        private let failure: VaultError
        private var remaining: Int

        init(store: VaultStore, failure: VaultError, times: Int) {
            self.store = store
            self.failure = failure
            remaining = times
        }

        func open() async throws -> OpenReport {
            if remaining > 0 {
                remaining -= 1
                throw failure
            }
            return try await store.open()
        }

        func lock() async { await store.lock() }
    }

    extension ScriptedOpening: VaultOpening {}  // in an extension, see ScriptedDocuments
#endif
