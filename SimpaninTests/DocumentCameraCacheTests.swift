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
import VaultCore

@testable import Simpanin

@Suite("Document camera cache")
struct DocumentCameraCacheTests {
    func caches() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "Caches-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func folder(in caches: URL) -> URL {
        caches.appending(path: DocumentCameraCache.folderName, directoryHint: .isDirectory)
    }

    /// The pages go, the folder stays: VisionKit's next pages land in it and take its class.
    @Test func thePagesVisionKitLeftAreRemoved() throws {
        let caches = try caches()
        defer { try? FileManager.default.removeItem(at: caches) }
        let scans = folder(in: caches).appending(path: "Scans")
        try FileManager.default.createDirectory(at: scans, withIntermediateDirectories: true)
        try Data(repeating: 0, count: 8).write(to: scans.appending(path: "page.jpg"))
        try DocumentCameraCache.clear(in: caches, protector: RecordingProtector())
        let left = try FileManager.default.contentsOfDirectory(atPath: folder(in: caches).path)
        #expect(left.isEmpty)
    }

    /// Created ahead of VisionKit with class Complete, so its files are locked from the moment they're
    /// written, before Simpanin removes them.
    @Test func theFolderIsCreatedWithClassComplete() throws {
        let caches = try caches()
        defer { try? FileManager.default.removeItem(at: caches) }
        let protector = RecordingProtector()
        try DocumentCameraCache.clear(in: caches, protector: protector)
        var isFolder: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: folder(in: caches).path, isDirectory: &isFolder))
        #expect(isFolder.boolValue)
        #expect(protector.calls.map(\.url.lastPathComponent) == [DocumentCameraCache.folderName])
        #expect(protector.calls.map(\.protection) == [.complete])
    }

    @Test func otherCachesStay() throws {
        let caches = try caches()
        defer { try? FileManager.default.removeItem(at: caches) }
        let other = caches.appending(path: "com.inez.Simpanin/keep.db")
        try FileManager.default.createDirectory(
            at: other.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([1]).write(to: other)
        try DocumentCameraCache.clear(in: caches, protector: RecordingProtector())
        #expect(FileManager.default.fileExists(atPath: other.path))
    }
}
