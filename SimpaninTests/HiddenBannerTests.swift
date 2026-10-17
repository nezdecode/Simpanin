//
//  HiddenBannerTests.swift
//  SimpaninTests
//
//  Created by Inez Amanda on 17/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import Testing
import VaultCore

@testable import Simpanin

/// "Jangan tampilkan di sini": which documents stay out of the expiry banner, and where that's kept.
@Suite("Hidden from the banner")
struct HiddenBannerTests {
    let today = CalendarDate(year: 2026, month: 10, day: 15)!
    let soon = CalendarDate(year: 2026, month: 10, day: 25)!
    let past = CalendarDate(year: 2026, month: 10, day: 1)!

    @Test func aHiddenDocumentIsLeftOut() {
        var hidden = HiddenBanner()
        let id = DocumentID()
        hidden.hide(id, expiry: past, today: today)
        #expect(hidden.hides(id, expiry: past, today: today))
        #expect(!hidden.hides(DocumentID(), expiry: past, today: today))
    }

    /// Hidden with the date it had: a changed date (an edit) brings it back.
    @Test func aHiddenDocumentComesBackWhenItsDateChanges() {
        var hidden = HiddenBanner()
        let id = DocumentID()
        hidden.hide(id, expiry: past, today: today)
        #expect(!hidden.hides(id, expiry: soon, today: today))
    }

    /// Another document, even of the same type and date, isn't hidden with it: a family has two SIM A.
    @Test func aNewDocumentOfTheSameTypeDoesntHideTheOld() {
        var hidden = HiddenBanner()
        hidden.hide(DocumentID(), expiry: past, today: today)
        #expect(!hidden.hides(DocumentID(), expiry: past, today: today))
    }

    /// Hidden while still to come, it shows once more on expiring; hidden again then, it stays hidden.
    @Test func aHiddenUpcomingDocumentReturnsOnceItExpires() {
        var hidden = HiddenBanner()
        let id = DocumentID()
        hidden.hide(id, expiry: soon, today: today)
        #expect(hidden.hides(id, expiry: soon, today: today))
        let later = CalendarDate(year: 2026, month: 11, day: 1)!
        #expect(!hidden.hides(id, expiry: soon, today: later))
        hidden.hide(id, expiry: soon, today: later)
        #expect(hidden.hides(id, expiry: soon, today: later))
    }

    @Test func orphanEntriesArePrunedButDeletedDocumentsKeepTheirs() {
        var hidden = HiddenBanner()
        let live = DocumentID()
        let inBin = DocumentID()
        let gone = DocumentID()
        for id in [live, inBin, gone] { hidden.hide(id, expiry: past, today: today) }
        let pruned = hidden.prune(keeping: [live, inBin])
        #expect(pruned)
        #expect(hidden.entries.map(\.id) == [live, inBin])
        let prunedAgain = hidden.prune(keeping: [live, inBin])
        #expect(!prunedAgain)
    }

    // MARK: The file

    func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "Projection-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func theHiddenListSurvivesARelaunch() throws {
        let projection = try folder()
        defer { try? FileManager.default.removeItem(at: projection) }
        let url = projection.appending(path: "hidden-banner.json")
        var hidden = HiddenBanner()
        hidden.hide(DocumentID(), expiry: past, today: today)
        try HiddenBannerFile(url: url, protector: RecordingProtector()).save(hidden)
        #expect(try HiddenBannerFile(url: url, protector: RecordingProtector()).load() == hidden)
    }

    /// Written through a temp file and a rename, given the projection's class, leaving no temp behind.
    @Test func theFileIsWrittenWholeWithItsClass() throws {
        let projection = try folder()
        defer { try? FileManager.default.removeItem(at: projection) }
        let protector = RecordingProtector()
        try HiddenBannerFile(url: projection.appending(path: "hidden-banner.json"), protector: protector).save(
            HiddenBanner())
        #expect(protector.calls.map(\.protection) == [.completeUntilFirstUserAuthentication])
        #expect(try FileManager.default.contentsOfDirectory(atPath: projection.path) == ["hidden-banner.json"])
    }

    /// It lives in the projection folder, which is kept out of iCloud and device backups.
    @Test func theHiddenListIsNotBackedUp() throws {
        let support = try folder()
        let container = try folder()
        defer {
            try? FileManager.default.removeItem(at: support)
            try? FileManager.default.removeItem(at: container)
        }
        let locations = VaultLocations(applicationSupport: support, appGroupContainer: container)
        try AppVault.prepareProjectionFolder(locations, protector: RecordingProtector())
        let url = HiddenBannerFile.url(in: locations)
        #expect(url.deletingLastPathComponent() == locations.projectionFolder)
        let values = try locations.projectionFolder.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
    }

    @Test func noFileYetIsAnEmptyList() throws {
        let projection = try folder()
        defer { try? FileManager.default.removeItem(at: projection) }
        let file = HiddenBannerFile(
            url: projection.appending(path: "hidden-banner.json"), protector: RecordingProtector())
        #expect(try file.load() == HiddenBanner())
    }
}
