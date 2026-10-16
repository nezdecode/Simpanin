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

    /// Every page is read, and their lines are parsed together in page order.
    @Test func everyPageIsRead() async throws {
        let fake = FakeRecognizer([Array(Self.ktp.prefix(2)), Array(Self.ktp.suffix(1))])
        let scan = model(fake)
        await scan.scanned([try page(), try page()])
        #expect(await fake.methods.count == 2)
        #expect(scan.lines == Self.ktp)
        #expect(scan.result?.fields.values[FieldKey.name] == "BUDI CONTOH")
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
