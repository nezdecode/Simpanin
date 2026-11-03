//
//  StartOverTests.swift
//  SimpaninTests
//
//  Created by Inez Amanda on 4/11/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import Testing

@testable import Simpanin

@Suite("Start over")
struct StartOverTests {
    let folder = FileManager.default.temporaryDirectory.appending(path: "StartOverTests-\(UUID().uuidString)")

    private func makeFolder(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: url.appending(path: "file"))
    }

    /// A folder whose contents can't be looked at, as `fileExists` can't tell from a missing one.
    private func lockedAway(_ parent: URL) throws -> URL {
        let child = parent.appending(path: "Vault")
        try makeFolder(child)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: parent.path)
        return child
    }

    private func unlock(_ parent: URL) {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: parent.path)
        try? FileManager.default.removeItem(at: folder)
    }

    @Test func aMissingFolderIsNotThere() {
        let lines = StartOver.removeFiles([folder.appending(path: "missing")])
        #expect(lines.map(\.result) == ["not there"])
        #expect(StartOver.succeeded(lines))
    }

    @Test func aFolderIsRemoved() throws {
        let vault = folder.appending(path: "Vault")
        try makeFolder(vault)
        defer { unlock(folder) }
        let lines = StartOver.removeFiles([vault])
        #expect(lines.map(\.result) == ["removed"])
        #expect(!FileManager.default.fileExists(atPath: vault.path))
    }

    @Test func anUnreadableFolderIsNeverTakenAsGone() throws {
        let parent = folder.appending(path: "locked")
        let vault = try lockedAway(parent)
        defer { unlock(parent) }
        let lines = StartOver.removeFiles([vault])
        #expect(!StartOver.succeeded(lines))
    }

    @Test func theKeysAreKeptWhenAFolderStays() throws {
        let parent = folder.appending(path: "locked")
        _ = try lockedAway(parent)
        defer { unlock(parent) }
        let locations = VaultLocations(applicationSupport: parent, appGroupContainer: folder.appending(path: "group"))
        let lines = StartOver.run(locations: locations, accessGroup: "test.simpanin.startover")
        #expect(lines.last == DeviceCheckLine(label: "delete vault keys", result: "skipped, a folder stayed"))
    }
}
