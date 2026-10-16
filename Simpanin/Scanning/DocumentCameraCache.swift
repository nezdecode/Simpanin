//
//  DocumentCameraCache.swift
//  Simpanin
//
//  Created by Inez Amanda on 16/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import OSLog
import VaultCore

/// VisionKit's document camera keeps every page it takes as an unencrypted JPEG in
/// `Library/Caches/com.apple.DocumentCamera` (seen on iOS 27). A scan may only live in memory until
/// it's saved, so the folder is emptied after every scan and at launch, and kept with class Complete.
nonisolated enum DocumentCameraCache {
    static let folderName = "com.apple.DocumentCamera"

    /// Removes what's in the folder and keeps the folder, with class Complete: VisionKit writes into it,
    /// and a new file takes its folder's class, so its pages are locked from the moment they're written.
    /// Any error is thrown, so the caller can log it.
    static func clear(in caches: URL, protector: any FileProtector) throws {
        let folder = caches.appending(path: folderName, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // Protected first, so a page that can't be removed never leaves the folder without its class.
        try protector.protect(folder, as: .complete)
        for item in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) {
            try FileManager.default.removeItem(at: item)
        }
    }

    /// Clears the app's own Caches. A failure is logged, never ignored: it would leave a page on disk.
    static func clear() {
        do {
            try clear(in: .cachesDirectory, protector: DataProtectionFileProtector())
        } catch {
            Logger.scan.error(
                "The document camera's pages weren't removed: \(ErrorSummary.describe(error), privacy: .public)")
        }
    }
}
