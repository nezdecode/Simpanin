//
//  SharedCopiesTests.swift
//  SimpaninTests
//
//  Created by Inez Amanda on 4/11/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import CoreGraphics
import Foundation
import ImageIO
import Synchronization
import Testing
import VaultCore

@testable import Simpanin

@Suite("Shared copies")
struct SharedCopiesTests {
    /// Protections and writes in the order they happened.
    final class Steps: FileProtector {
        private let log = Mutex<[String]>([])
        var all: [String] { log.withLock { $0 } }
        func protect(_ url: URL, as protection: FileProtectionClass) throws {
            log.withLock { $0.append("protect \(url.lastPathComponent) \(protection)") }
        }
        func wrote(_ url: URL) { log.withLock { $0.append("write \(url.lastPathComponent)") } }
    }

    func temporary() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "tmp-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func contents(_ url: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: url.path).sorted()
    }

    /// The type, the purpose and the day; never the label or the number, which the file list would show.
    @Test func aSharedFileNameHasNoLabelOrNumber() throws {
        let date = try #require(ISO8601DateFormatter().date(from: "2026-11-04T09:00:00Z"))
        let utc = try #require(TimeZone(identifier: "UTC"))
        func name(_ purpose: String, page: Int = 1, of count: Int = 1) -> String {
            SharedCopies.fileName(type: "KTP", purpose: purpose, page: page, of: count, date: date, timeZone: utc)
        }
        #expect(name("Sewa kos") == "KTP - Sewa kos - Simpanin 4 Nov 2026.jpg")
        #expect(name("Sewa kos", page: 3, of: 3) == "KTP - Sewa kos - Simpanin 4 Nov 2026 - hal 3.jpg")
        // Characters a target can refuse in a name go, and a long purpose is shortened.
        #expect(name("Bank/BCA: rekening") == "KTP - Bank BCA rekening - Simpanin 4 Nov 2026.jpg")
        #expect(
            name(String(repeating: "a", count: 40))
                == "KTP - \(String(repeating: "a", count: 30)) - Simpanin 4 Nov 2026.jpg")
        #expect(name("///") == "KTP - Simpanin 4 Nov 2026.jpg")
    }

    /// The class is the folder's before the first byte lands, so a copy is never at tmp's default.
    @Test func theFolderIsProtectedBeforeAFileIsWritten() throws {
        let temporary = try temporary()
        defer { try? FileManager.default.removeItem(at: temporary) }
        let steps = Steps()
        let copies = SharedCopies(temporary: temporary, protector: steps) { data, url in
            steps.wrote(url)
            try SharedCopies.writeComplete(data, url)
        }
        let folder = try copies.makeFolder()
        _ = try copies.write(try SyntheticPhoto.image(width: 40, height: 30), named: "a.jpg", in: folder)
        #expect(
            steps.all == [
                "protect \(SharedCopies.folderName) complete", "protect \(folder.lastPathComponent) complete",
                "write a.jpg",
            ])
        #expect(folder.deletingLastPathComponent().lastPathComponent == SharedCopies.folderName)
    }

    @Test func aFullDiskWhileWritingIsStorageFull() throws {
        let temporary = try temporary()
        defer { try? FileManager.default.removeItem(at: temporary) }
        let copies = SharedCopies(temporary: temporary, protector: RecordingProtector()) { _, _ in
            throw CocoaError(.fileWriteOutOfSpace)
        }
        let folder = try copies.makeFolder()
        #expect(throws: VaultError.storageFull) {
            try copies.write(try SyntheticPhoto.image(width: 40, height: 30), named: "a.jpg", in: folder)
        }
    }

    @Test func aCopyHasNoMetadata() throws {
        let temporary = try temporary()
        defer { try? FileManager.default.removeItem(at: temporary) }
        let copies = SharedCopies(temporary: temporary, protector: RecordingProtector())
        let url = try copies.write(
            try SyntheticPhoto.image(width: 40, height: 30), named: "a.jpg", in: try copies.makeFolder())
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        #expect(CGImageSourceGetType(source) as String? == "public.jpeg")
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        // ImageIO always writes the pixel size and colour space; nothing that says where, when or with what.
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let allowed: Set<CFString> = [
            kCGImagePropertyExifPixelXDimension, kCGImagePropertyExifPixelYDimension, kCGImagePropertyExifColorSpace,
        ]
        #expect(Set(exif.keys).isSubset(of: allowed))
        #expect(properties[kCGImagePropertyGPSDictionary] == nil)
        #expect(properties[kCGImagePropertyTIFFDictionary] == nil)
        #expect(properties[kCGImagePropertyIPTCDictionary] == nil)
    }

    @Test func removeDeletesOneShareOnly() throws {
        let temporary = try temporary()
        defer { try? FileManager.default.removeItem(at: temporary) }
        let copies = SharedCopies(temporary: temporary, protector: RecordingProtector())
        let first = try copies.makeFolder()
        let second = try copies.makeFolder()
        try copies.remove(first)
        #expect(!FileManager.default.fileExists(atPath: first.path))
        #expect(FileManager.default.fileExists(atPath: second.path))
    }

    @Test func clearEmptiesTheSharedCopiesFolder() throws {
        let temporary = try temporary()
        defer { try? FileManager.default.removeItem(at: temporary) }
        let copies = SharedCopies(temporary: temporary, protector: RecordingProtector())
        _ = try copies.write(
            try SyntheticPhoto.image(width: 40, height: 30), named: "a.jpg", in: try copies.makeFolder())
        try copies.clear()
        #expect(try contents(temporary).isEmpty)
    }

    /// Apple's copies sit at CompleteUntilFirstUserAuthentication, readable while the phone is locked.
    @Test func theShareSheetsOwnCopiesAreDeletedToo() throws {
        let temporary = try temporary()
        defer { try? FileManager.default.removeItem(at: temporary) }
        let sheet = temporary.appending(path: ".com.apple.ShareSheet.Activity.AbCdEf/.representation/x.jpg")
        try FileManager.default.createDirectory(
            at: sheet.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 1, count: 8).write(to: sheet)
        try Data(repeating: 2, count: 8).write(to: temporary.appending(path: "someone-else.tmp"))
        try FileManager.default.createDirectory(
            at: temporary.appending(path: "com.apple.Other"), withIntermediateDirectories: true)
        try SharedCopies(temporary: temporary, protector: RecordingProtector()).clear()
        #expect(try contents(temporary) == ["com.apple.Other", "someone-else.tmp"])
    }

    @Test func clearWithNothingThereSucceeds() throws {
        let temporary = try temporary()
        defer { try? FileManager.default.removeItem(at: temporary) }
        try SharedCopies(temporary: temporary, protector: RecordingProtector()).clear()
        #expect(try contents(temporary).isEmpty)
    }
}
