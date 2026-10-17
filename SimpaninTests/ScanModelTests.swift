//
//  ScanModelTests.swift
//  SimpaninTests
//
//  Created by Inez Amanda on 15/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import CoreGraphics
import Parsers
import Testing
import VaultCore

@testable import Simpanin

/// Synthetic lines only; NIKs start with 00.
@MainActor
@Suite("Scan model")
struct ScanModelTests {
    static let ktp = ["PROVINSI DKI JAKARTA", "NIK : 0012341708900001", "Nama : BUDI CONTOH"]
    static let sim = [
        "SURAT IZIN MENGEMUDI", "C", "0000-0000-000001", "1. BUDI CONTOH", "2. JAKARTA, 17-08-1990", "04-01-2027",
    ]

    /// The back of an older SIM as printed: the title and numbered rules, and no number.
    static let titledBack = ["SURAT IZIN MENGEMUDI", "1. MEMALSUKAN SIM DILARANG", "2. SIM TIDAK DIPINJAMKAN"]

    /// The back of a card: no title, and a date alone on its line, which read together with the front
    /// would be a second expiry.
    static let back = ["KETENTUAN PENGGUNAAN", "04-01-2032"]

    /// A blank page: the stand-in recognizer never looks at it.
    func page() throws -> CGImage {
        let context = try #require(
            CGContext(
                data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        return try #require(context.makeImage())
    }

    func model(_ fake: FakeRecognizer) -> ScanModel {
        ScanModel(recognizer: { fake.using($0) }, today: { CalendarDate(year: 2026, month: 10, day: 15)! })
    }

    @Test func aKTPIsReadAndParsed() async throws {
        let scan = model(FakeRecognizer([Self.ktp]))
        await scan.scanned([try page()])
        #expect(scan.state == .read)
        #expect(scan.result?.type == .ktp)
        #expect(scan.result?.fields.values[FieldKey.nik] == "0012341708900001")
    }

    @Test func aSIMIsReadAndParsed() async throws {
        let scan = model(FakeRecognizer([Self.sim]))
        await scan.scanned([try page()])
        #expect(scan.result?.type == .simC)
    }

    /// Text the parsers don't know reads fine, with no result; the review screen offers "Lainnya".
    @Test func unknownTextHasNoResult() async throws {
        let scan = model(FakeRecognizer([["STRUK BELANJA", "TOTAL 10.000"]]))
        await scan.scanned([try page()])
        #expect(scan.state == .read)
        #expect(scan.result == nil)
    }

    /// Every page is read, and the debug screen sees all their lines; the fields come from the first page
    /// that is a KTP or SIM, never from the pages mixed together.
    @Test func everyPageIsRead() async throws {
        let fake = FakeRecognizer([Self.ktp, Self.back])
        let scan = model(fake)
        await scan.scanned([try page(), try page()])
        #expect(await fake.methods.count == 2)
        #expect(scan.lines == Self.ktp + Self.back)
        #expect(scan.result?.fields.values[FieldKey.name] == "BUDI CONTOH")
    }

    /// A date on the back of a SIM never mixes in with the front's.
    @Test func onlyTheFrontPageIsParsed() async throws {
        let scan = model(FakeRecognizer([Self.sim, Self.back]))
        await scan.scanned([try page(), try page()])
        #expect(scan.result?.expiry == CalendarDate(year: 2027, month: 1, day: 4))
        #expect(scan.result?.expiryNeedsCheck == false)
    }

    /// A back that reads as a SIM too doesn't hide the front: the page with a number is the front.
    @Test func aTitledBackPageDoesntHideTheFront() async throws {
        let scan = model(FakeRecognizer([Self.titledBack, Self.sim]))
        await scan.scanned([try page(), try page()])
        #expect(scan.result?.type == .simC)
        #expect(scan.result?.fields.values[FieldKey.name] == "BUDI CONTOH")
    }

    /// With no number read on any page, the page that gave the most fields is the front, not an empty back.
    @Test func aFrontWithoutItsNumberStillBeatsAnEmptyBack() async throws {
        let front = Self.sim.filter { $0 != "0000-0000-000001" }
        let scan = model(FakeRecognizer([Self.titledBack, front]))
        await scan.scanned([try page(), try page()])
        #expect(scan.result?.fields.values[FieldKey.name] == "BUDI CONTOH")
    }

    /// The back may be scanned first; the front is found as the second page.
    @Test func theFrontIsFoundWhenItIsTheSecondPage() async throws {
        // A back on either side: read together, its date after the front's birth line would be a second expiry.
        let scan = model(FakeRecognizer([Self.back, Self.sim, Self.back]))
        await scan.scanned([try page(), try page(), try page()])
        #expect(scan.result?.type == .simC)
        #expect(scan.result?.expiry == CalendarDate(year: 2027, month: 1, day: 4))
    }

    /// The DEBUG screen compares the two Vision requests on the same pages.
    @Test func anotherMethodRereadsTheSamePages() async throws {
        let fake = FakeRecognizer([["STRUK"], Self.ktp])
        let scan = model(fake)
        await scan.scanned([try page()])
        #expect(scan.result == nil)
        await scan.read(using: .document)
        #expect(await fake.methods == [.text, .document])
        #expect(scan.method == .document)
        #expect(scan.result?.type == .ktp)
    }

    @Test func aFailedReadKeepsNoResult() async throws {
        let scan = model(FakeRecognizer([Self.ktp], failing: true))
        await scan.scanned([try page()])
        #expect(scan.state == .failed)
        #expect(scan.result == nil)
        #expect(scan.lines.isEmpty)
    }

    @Test func discardDropsEverything() async throws {
        let scan = model(FakeRecognizer([Self.ktp]))
        await scan.scanned([try page()])
        scan.discard()
        #expect(scan.state == .empty)
        #expect(scan.pages.isEmpty)
        #expect(scan.lines.isEmpty)
        #expect(scan.result == nil)
    }

    /// Once a scan is dropped, the pages left aren't read: they'd keep the dropped pages in memory and
    /// Vision busy.
    @Test func aDiscardedScanReadsNoFurtherPages() async throws {
        let fake = FakeRecognizer([Self.ktp, Self.ktp], gated: true)
        let scan = model(fake)
        let pages = [try page(), try page()]
        let reading = Task { await scan.scanned(pages) }
        try #require(await fake.waitUntilReading())
        scan.discard()
        await fake.release()
        await reading.value
        #expect(await fake.methods.count == 1)
    }

    /// The screen that started a read cancels it when it goes away, also when locking the vault removes
    /// it before it could drop the scan. A cancelled read reads no further pages and drops the scan.
    @Test func aCancelledReadDropsTheScan() async throws {
        let fake = FakeRecognizer([Self.ktp, Self.ktp], gated: true)
        let scan = model(fake)
        let pages = [try page(), try page()]
        let reading = Task { await scan.scanned(pages) }
        try #require(await fake.waitUntilReading())
        reading.cancel()
        await fake.release()
        await reading.value
        #expect(await fake.methods.count == 1)
        #expect(scan.state == .empty)
        #expect(scan.pages.isEmpty)
        #expect(scan.lines.isEmpty)
    }

    /// The vault can lock while Vision is still reading; the read that finishes later must not bring
    /// the scan back.
    @Test func aScanDiscardedWhileReadingStaysDiscarded() async throws {
        let fake = FakeRecognizer([Self.ktp], gated: true)
        let scan = model(fake)
        let pages = [try page()]
        let reading = Task { await scan.scanned(pages) }
        try #require(await fake.waitUntilReading())
        #expect(scan.state == .reading)
        scan.discard()
        await fake.release()
        await reading.value
        #expect(scan.state == .empty)
        #expect(scan.pages.isEmpty)
        #expect(scan.lines.isEmpty)
        #expect(scan.result == nil)
    }
}
