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
    import PhotosUI
    import SwiftUI
    import VaultCore

    /// Launch arguments the UI tests use. `-SimpaninUITest` starts on a fresh throwaway vault
    /// with an in-memory key. `-SimpaninUITestOpenError <case>` makes opening fail, so a test
    /// lands on a recovery screen; `-SimpaninUITestPasscode notSet` acts as if there's no passcode.
    /// `-SimpaninUITestBrokenOldVault` puts a folder VaultCore can't read into Data lama.
    /// `-SimpaninUITestScan` makes "+" skip the camera, which the simulator lacks, and read a synthetic KTP;
    /// `-SimpaninUITestScanKTPAndSIM` does the same with two pages, a synthetic KTP and SIM A.
    /// `-SimpaninUITestSlowRead` makes each synthetic page take eight seconds to read, longer than a UI test
    /// waits for the screen to settle after a tap.
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
        /// `-SimpaninUITestDeleteError` fails every Hapus; `-SimpaninUITestBinError` every Pulihkan and
        /// Hapus permanen; `-SimpaninUITestSlowRestore` makes each Pulihkan take eight seconds, and
        /// `-SimpaninUITestSlowSave` each Simpan, an edit's too; `-SimpaninUITestEditError` fails every edit;
        /// `-SimpaninUITestLaterPagesFail` fails every page after the first, so page 1 still shows and a share
        /// stops at page 2.
        static func documentStore(for vault: AppVault) -> any DocumentStoring & PageReading {
            let count = value(after: "-SimpaninUITestLoadError").flatMap(Int.init)
            let failsDeletes = ProcessInfo.processInfo.arguments.contains("-SimpaninUITestDeleteError")
            let failsBin = ProcessInfo.processInfo.arguments.contains("-SimpaninUITestBinError")
            let slowRestore = ProcessInfo.processInfo.arguments.contains("-SimpaninUITestSlowRestore")
            let slowSave = ProcessInfo.processInfo.arguments.contains("-SimpaninUITestSlowSave")
            let failsEdits = ProcessInfo.processInfo.arguments.contains("-SimpaninUITestEditError")
            let failsLaterPages = ProcessInfo.processInfo.arguments.contains("-SimpaninUITestLaterPagesFail")
            guard count != nil || failsDeletes || failsBin || slowRestore || slowSave || failsEdits || failsLaterPages
            else {
                return vault.store
            }
            return ScriptedDocuments(
                store: vault.store, failingLoads: count ?? 0, failsDeletes: failsDeletes, failsBin: failsBin,
                slowRestore: slowRestore, slowSave: slowSave, failsEdits: failsEdits, failsLaterPages: failsLaterPages)
        }

        /// `-SimpaninUITestRecordingAfterLock`: Kunci also acts as if a recording started, and it never stops.
        static var recordsAfterLock: Bool {
            isActive && ProcessInfo.processInfo.arguments.contains("-SimpaninUITestRecordingAfterLock")
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

        /// `-SimpaninUITestWelcome`: the throwaway vault starts empty, so the welcome shows. Without it every test
        /// starts on the list, as it did before the welcome existed.
        static var showsWelcome: Bool {
            isActive && ProcessInfo.processInfo.arguments.contains("-SimpaninUITestWelcome")
        }

        /// `-SimpaninUITestNoCamera`: "+" acts as on a phone without a document camera, which the iOS 27
        /// simulator otherwise has.
        static var hidesCamera: Bool {
            isActive && ProcessInfo.processInfo.arguments.contains("-SimpaninUITestNoCamera")
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

        /// A card's width in pixels; the SIM's page is one wider, which is how the recognizer below tells them
        /// apart, so a rescan reads the same. A page two wider reads no text, like a photo of no document.
        private static let cardWidth = 1_712

        /// Cards with a photo box and lines, no text, so the viewer and the strip show something in screenshots.
        static var syntheticPages: [CGImage] {
            (scansKTPAndSIM ? [cardWidth, cardWidth + 1] : [cardWidth]).compactMap(cardPage)
        }

        private static func cardPage(width: Int) -> CGImage? {
            let height = 1_080
            guard
                let context = CGContext(
                    data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
            else { return nil }
            context.setFillColor(red: 0.62, green: 0.78, blue: 0.9, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.setFillColor(red: 0.85, green: 0.85, blue: 0.85, alpha: 1)
            context.fill(CGRect(x: width - 460, y: 200, width: 360, height: 460))
            context.setFillColor(red: 0.2, green: 0.25, blue: 0.3, alpha: 1)
            for line in 0..<6 {
                context.fill(CGRect(x: 100, y: 860 - line * 120, width: line == 0 ? 900 : 700, height: 40))
            }
            return context.makeImage()
        }

        /// `-SimpaninUITestPickPhotos <mode>`: UI tests can't drive the system picker, so Pilih dari Foto opens
        /// with one synthetic photo already ticked, and Tambah hands it over through `SyntheticPhotos`. The
        /// mode is `ktp`, `blank` (a photo with no document), `fails` (a photo that can't be opened) or `slow`
        /// (eight seconds to hand it over).
        static var picksPhotos: String? { isActive ? value(after: "-SimpaninUITestPickPhotos") : nil }

        static var syntheticPhotoSelection: [PhotosPickerItem] {
            picksPhotos == nil ? [] : [PhotosPickerItem(itemIdentifier: "synthetic-ktp")]
        }

        /// The synthetic card as a JPEG file, read by `SyntheticRecognizer` like a scanned one.
        struct SyntheticPhotos: PhotoLoading {
            let mode: String

            func data(for item: PhotosPickerItem) async throws -> Data? {
                if mode == "slow" { try await Task.sleep(for: .seconds(8)) }
                if mode == "fails" { return Data("not a photo".utf8) }
                let width = mode == "blank" ? cardWidth + 2 : cardWidth
                return UITestSetup.cardPage(width: width).flatMap(PageEncoding.jpeg)
            }
        }

        /// A synthetic KTP whose name is marked, so the review screen shows Periksa lagi, and on the wider page
        /// a synthetic SIM A with the same NIK as its number.
        struct SyntheticRecognizer: TextRecognizer {
            func lines(in page: CGImage) async throws -> [String] {
                if UITestSetup.readsSlowly { try await Task.sleep(for: .seconds(8)) }
                switch page.width {
                case cardWidth + 1: return Self.sim
                case cardWidth + 2: return []
                default: return Self.ktp
                }
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

        /// `-SimpaninUITestPasscode notSet`: a phone without a passcode; `turnedOff`, see `lockController(for:)`.
        static var passcode: PasscodeState {
            value(after: "-SimpaninUITestPasscode") == "notSet" ? .notSet : .set
        }

        @MainActor
        static func lockController(for vault: AppVault) -> LockController {
            let opener: any VaultOpening =
                openFailure.map { ScriptedOpening(store: vault.store, failure: $0.error, times: $0.times) }
                ?? vault.store
            let passcode = passcode
            // `turnedOff`: the passcode is there while the vault opens and gone once it's open, as when it's
            // turned off in Settings while Simpanin runs.
            let turnedOff = value(after: "-SimpaninUITestPasscode") == "turnedOff"
            let opened = OpenedLock()
            // The same launch path as the app: the lock starts from the stored choice.
            let lock = LockController(
                vault: opener, autoLock: AutoLock.stored(in: settings), settings: settings,
                passcode: { turnedOff && opened.lock?.state == .unlocked ? .notSet : passcode },
                vaultExists: { VaultStore.vaultExists(in: vault.locations.root) },
                vaultIsEmpty: { showsWelcome ? try VaultStore.isEmpty(in: vault.locations.root) : false },
                protectedDataAvailable: { true })
            opened.lock = lock
            return lock
        }

        /// Lets the passcode check see the lock it belongs to, which only exists once that check is made.
        @MainActor
        private final class OpenedLock {
            weak var lock: LockController?
        }
    }

    /// Fails the first loads of the document list, so a test sees the "couldn't load" state and
    /// then "Coba lagi" working, and can fail every delete. Everything else goes to the real (throwaway) store.
    actor ScriptedDocuments {
        private let store: VaultStore
        private var failingLoads: Int
        private let failsDeletes: Bool
        private let failsBin: Bool
        private let slowRestore: Bool
        private let slowSave: Bool
        private let failsEdits: Bool
        private let failsLaterPages: Bool

        init(
            store: VaultStore, failingLoads: Int, failsDeletes: Bool = false, failsBin: Bool = false,
            slowRestore: Bool = false, slowSave: Bool = false, failsEdits: Bool = false, failsLaterPages: Bool = false
        ) {
            self.store = store
            self.failingLoads = failingLoads
            self.failsDeletes = failsDeletes
            self.failsBin = failsBin
            self.slowRestore = slowRestore
            self.slowSave = slowSave
            self.failsEdits = failsEdits
            self.failsLaterPages = failsLaterPages
        }

        func documents() async throws -> [VaultCore.Document] {
            if failingLoads > 0 {
                failingLoads -= 1
                throw VaultError.locked
            }
            return try await store.documents()
        }

        func recentlyDeleted() async throws -> [VaultCore.Document] { try await store.recentlyDeleted() }
        func fields(of id: DocumentID) async throws -> DocumentFields { try await store.fields(of: id) }

        // swiftlint:disable:next function_parameter_count - mirrors VaultStore.createDocument
        func createDocument(
            type: DocumentType, label: String?, expiry: CalendarDate?, pinned: Bool, fields: DocumentFields,
            pages: [Data]
        ) async throws -> DocumentID {
            if slowSave { try await Task.sleep(for: .seconds(8)) }
            return try await store.createDocument(
                type: type, label: label, expiry: expiry, pinned: pinned, fields: fields, pages: pages)
        }

        // swiftlint:disable:next function_parameter_count - mirrors VaultStore.editDocument
        func editDocument(
            _ id: DocumentID, type: DocumentType, label: String?, expiry: CalendarDate?, pinned: Bool,
            fields: DocumentFields
        ) async throws {
            if failsEdits { throw VaultError.fileUnavailable }
            if slowSave { try await Task.sleep(for: .seconds(8)) }
            try await store.editDocument(id, type: type, label: label, expiry: expiry, pinned: pinned, fields: fields)
        }

        func delete(_ id: DocumentID) async throws {
            if failsDeletes { throw VaultError.fileUnavailable }
            try await store.delete(id)
        }
        func restore(_ id: DocumentID) async throws {
            if failsBin { throw VaultError.fileUnavailable }
            if slowRestore { try await Task.sleep(for: .seconds(8)) }
            try await store.restore(id)
        }
        func deletePermanently(_ id: DocumentID) async throws {
            if failsBin { throw VaultError.fileUnavailable }
            try await store.deletePermanently(id)
        }
        func pageData(_ pageID: PageID, of id: DocumentID) async throws -> Data {
            if failsLaterPages, try await store.documents().first(where: { $0.id == id })?.pageIDs.first != pageID {
                throw VaultError.authenticationFailed
            }
            return try await store.pageData(pageID, of: id)
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
