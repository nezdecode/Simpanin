//
//  FileChangesTests.swift
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

@Suite("File changes")
struct FileChangesTests {
    func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "FileChangesTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func aNewFileInASubfolderIsReported() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data([1, 2, 3]).write(to: root.appending(path: "before.jpg"))
        let snapshot = FileChanges(folders: [root])
        try FileManager.default.createDirectory(at: root.appending(path: "Scans"), withIntermediateDirectories: true)
        try Data(repeating: 0, count: 10).write(to: root.appending(path: "Scans/page-1.jpg"))
        #expect(snapshot.changes() == [.init(path: "\(root.lastPathComponent)/Scans/page-1.jpg", size: 10)])
    }

    /// VisionKit might write into a file that was already there.
    @Test func aChangedFileIsReported() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appending(path: "cache.db")
        try Data([1]).write(to: file)
        try FileManager.default.setAttributes(
            [.modificationDate: Date.now.addingTimeInterval(-60)], ofItemAtPath: file.path)
        let snapshot = FileChanges(folders: [root])
        try Data([1, 2]).write(to: file)
        #expect(snapshot.changes() == [.init(path: "\(root.lastPathComponent)/cache.db", size: 2)])
    }

    @Test func nothingChangedReportsNothing() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data([1]).write(to: root.appending(path: "untouched"))
        #expect(FileChanges(folders: [root]).changes().isEmpty)
    }
}
