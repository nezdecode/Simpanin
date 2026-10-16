//
//  DocumentCameraCacheTests.swift
//  SimpaninTests
//
//  Created by Inez Amanda on 16/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import Testing

@testable import Simpanin

@Suite("Document camera cache")
struct DocumentCameraCacheTests {
    func caches() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "Caches-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func thePagesVisionKitLeftAreRemoved() throws {
        let caches = try caches()
        defer { try? FileManager.default.removeItem(at: caches) }
        let scans = caches.appending(path: "\(DocumentCameraCache.folderName)/Scans")
        try FileManager.default.createDirectory(at: scans, withIntermediateDirectories: true)
        try Data(repeating: 0, count: 8).write(to: scans.appending(path: "page.jpg"))
        try DocumentCameraCache.clear(in: caches)
        #expect(!FileManager.default.fileExists(atPath: caches.appending(path: DocumentCameraCache.folderName).path))
    }

    @Test func otherCachesStay() throws {
        let caches = try caches()
        defer { try? FileManager.default.removeItem(at: caches) }
        let other = caches.appending(path: "com.inez.Simpanin/keep.db")
        try FileManager.default.createDirectory(
            at: other.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([1]).write(to: other)
        try FileManager.default.createDirectory(
            at: caches.appending(path: DocumentCameraCache.folderName), withIntermediateDirectories: true)
        try DocumentCameraCache.clear(in: caches)
        #expect(FileManager.default.fileExists(atPath: other.path))
    }

    /// Most launches find nothing to remove; that's not an error.
    @Test func nothingToRemoveIsFine() throws {
        let caches = try caches()
        defer { try? FileManager.default.removeItem(at: caches) }
        try DocumentCameraCache.clear(in: caches)
    }
}
