//
//  DeviceChecksTests.swift
//  SimpaninTests
//
//  Created by Inez Amanda on 14/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import Testing

@testable import Simpanin

/// The checks themselves only mean something on a phone. Here they run on the simulator to
/// prove the report shows labels and statuses only, and that they clean up after themselves.
@Suite("Device checks")
struct DeviceChecksTests {
    func makeBase() throws -> URL {
        let base = FileManager.default.temporaryDirectory.appending(
            path: "Checks-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    /// Nothing that could be a file name, an id or a value.
    func expectLabelsOnly(_ lines: [DeviceCheckLine]) {
        let uuid = /[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-/
        for line in lines {
            let text = "\(line.label) \(line.result)"
            #expect(text.firstMatch(of: uuid) == nil, "\(text)")
            #expect(!text.contains(".enc") && !text.contains(".json") && !text.contains(".tmp"), "\(text)")
        }
    }

    @Test func vaultProtectionReportsEveryFileAndFolderByLabel() async throws {
        let base = try makeBase()
        defer { try? FileManager.default.removeItem(at: base) }
        let lines = try await DeviceChecks.scratchVaultProtection(
            applicationSupport: base.appending(path: "Support"), appGroup: base.appending(path: "Group"))
        let labels = Set(lines.map(\.label))
        #expect(
            labels.isSuperset(of: [
                "vault folder", "pages folder", "vault header", "index", "page 1", "projection", "projection folder",
            ]))
        expectLabelsOnly(lines)
        #expect(!FileManager.default.fileExists(atPath: base.appending(path: "Support/DeviceCheck").path))
    }

    @Test func renameAndFolderChecksCleanUp() throws {
        let base = try makeBase()
        defer { try? FileManager.default.removeItem(at: base) }
        let lines = try DeviceChecks.renameKeepsClass(in: base) + DeviceChecks.newFileTakesFolderClass(in: base)
        #expect(lines.count >= 2)
        expectLabelsOnly(lines)
        #expect(try FileManager.default.contentsOfDirectory(atPath: base.path).isEmpty)
    }

    @Test func reportHasAHeaderAndOneLinePerResult() {
        let report = DeviceChecks.report(
            device: ["iOS 26.5"],
            lines: [DeviceCheckLine(label: "index", result: "NSFileProtectionComplete")])
        #expect(report.hasPrefix("Simpanin device checks"))
        #expect(report.contains("iOS 26.5"))
        #expect(report.contains("index: NSFileProtectionComplete"))
    }
}
