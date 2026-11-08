//
//  AppVaultTests.swift
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
import VaultCore

@testable import Simpanin

/// The simulator doesn't store protection classes (they read back as nil), so the read-back
/// check only runs on a real device.
let isSimulator: Bool = {
    #if targetEnvironment(simulator)
        true
    #else
        false
    #endif
}()

@Suite("App vault setup")
struct AppVaultTests {
    @Test func protectorAsksForTheClassVaultCoreNames() {
        #expect(DataProtectionFileProtector.protectionType(for: .complete) == .complete)
        #expect(
            DataProtectionFileProtector.protectionType(for: .completeUntilFirstUserAuthentication)
                == .completeUntilFirstUserAuthentication)
    }

    /// Tests run the Debug build, which must never reach the App Store app's vault, key or projection.
    @Test func debugBuildUsesItsOwnKeychainGroupAndAppGroup() throws {
        let group = try #require(AppConfiguration.keychainAccessGroup)
        #expect(group.hasSuffix(".simpanin.vault.dev"))
        #expect(group.count > ".simpanin.vault.dev".count)  // the team prefix is filled in
        #expect(AppConfiguration.appGroup == "group.com.inez.Simpanin.dev")
        #expect(Bundle.main.bundleIdentifier == "com.inez.Simpanin.dev")
        let faceID = Bundle.main.object(forInfoDictionaryKey: "NSFaceIDUsageDescription") as? String
        #expect(faceID == "Simpanin memakai Face ID untuk membuka vault dokumenmu.")
    }

    @Test func infoPlistNamesTheAppAndItsCategory() {
        #expect(Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String == "Simpanin Dev")
        #expect(
            Bundle.main.object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String
                == "public.app-category.utilities")
    }

    @Test func infoPlistNamesTheAppIcon() {
        let icons = Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any]
        let primary = icons?["CFBundlePrimaryIcon"] as? [String: Any]
        #expect(primary?["CFBundleIconName"] as? String == "AppIcon")
    }

    @Test func appGroupContainerIsAvailable() throws {
        let group = try #require(AppConfiguration.appGroup)
        #expect(FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) != nil)
    }

    /// projection.json is plaintext, so it stays out of iCloud and device backups.
    @Test func backupExclusionIsSetOnAFolder() throws {
        var folder = FileManager.default.temporaryDirectory.appending(
            path: "Backup-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try AppVault.excludeFromBackup(folder)
        folder.removeAllCachedResourceValues()
        #expect(try folder.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
    }

    /// iOS doesn't let the app change the App Group container itself (error 513 on a device,
    /// though the simulator allows it), so the projection gets a folder of its own.
    @Test func projectionFolderIsPreparedAndExcludedFromBackup() throws {
        let base = FileManager.default.temporaryDirectory.appending(path: "Projection-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: base) }
        let locations = VaultLocations(
            applicationSupport: base.appending(path: "Support"), appGroupContainer: base.appending(path: "Group"))
        try FileManager.default.createDirectory(
            at: base.appending(path: "Group"), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: locations.oldProjection)
        let other = base.appending(path: "Group/keep.txt")
        try Data("keep".utf8).write(to: other)

        for _ in 1...2 {
            try AppVault.prepareProjectionFolder(locations, protector: NoFileProtection())
        }
        var folder = locations.projectionFolder
        folder.removeAllCachedResourceValues()
        #expect(try folder.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
        // The old plaintext copy goes; the projection is written again on the next unlock.
        #expect(!FileManager.default.fileExists(atPath: locations.oldProjection.path))
        #expect(FileManager.default.fileExists(atPath: other.path))
    }

    @Test func launchPreparesTheRealProjectionFolder() throws {
        // The test host launched the app, so the real App Group container has been through launch.
        let group = try #require(AppConfiguration.appGroup)
        let container = try #require(
            FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group))
        var folder = container.appending(path: "Projection", directoryHint: .isDirectory)
        folder.removeAllCachedResourceValues()
        #expect(try folder.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
    }

    @Test func locations() {
        let support = URL(filePath: "/Support", directoryHint: .isDirectory)
        let group = URL(filePath: "/Group", directoryHint: .isDirectory)
        let locations = VaultLocations(applicationSupport: support, appGroupContainer: group)
        #expect(locations.root.path == "/Support/Vault")
        #expect(locations.quarantine.path == "/Support/Quarantine")
        #expect(locations.projection.path == "/Group/Projection/projection.json")
        #expect(locations.oldProjection.path == "/Group/projection.json")
    }

    /// S1 from the review notes, read back from the file system.
    @Test(.enabled(if: !isSimulator, "The simulator doesn't store protection classes"))
    func vaultFilesAndFoldersHaveTheirClassOnDevice() async throws {
        let base = FileManager.default.temporaryDirectory.appending(path: "S1-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: base) }
        let locations = VaultLocations(
            applicationSupport: base.appending(path: "Support"), appGroupContainer: base.appending(path: "Group"))
        let store = VaultStore(
            rootDirectory: locations.root, projectionURL: locations.projection, keyStore: PreviewKeyStore(),
            fileProtector: DataProtectionFileProtector())
        try await store.open()
        _ = try await store.createDocument(
            type: .ktp, expiry: nil, pinned: false, fields: DocumentFields([FieldKey.nik: "0012345678901234"]),
            pages: [Data(repeating: 7, count: 2_000)])

        func protection(_ url: URL) throws -> FileProtectionType? {
            try FileManager.default.attributesOfItem(atPath: url.path)[.protectionKey] as? FileProtectionType
        }
        let vaultItems =
            [locations.root]
            + (try FileManager.default.subpathsOfDirectory(atPath: locations.root.path))
            .map { locations.root.appending(path: $0) }
        #expect(vaultItems.count >= 5)  // the folder, pages/, vault.json, index.enc, one page
        for url in vaultItems {
            #expect(try protection(url) == .complete, "\(url.lastPathComponent)")
        }
        #expect(try protection(locations.projection) == .completeUntilFirstUserAuthentication)
        #expect(
            try protection(locations.projection.deletingLastPathComponent()) == .completeUntilFirstUserAuthentication)
    }
}
