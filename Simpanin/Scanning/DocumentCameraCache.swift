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

/// VisionKit's document camera keeps every page it takes as an unencrypted JPEG in
/// `Library/Caches/com.apple.DocumentCamera` (seen on iOS 27). A scan may only live in memory until
/// it's saved, so the folder is removed after every scan and at launch.
nonisolated enum DocumentCameraCache {
    static let folderName = "com.apple.DocumentCamera"

    /// A missing folder is fine; any other error is thrown, so the caller can log it.
    static func clear(in caches: URL) throws {
        do {
            try FileManager.default.removeItem(at: caches.appending(path: folderName, directoryHint: .isDirectory))
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            return
        }
    }

    /// Clears the app's own Caches. A failure is logged, never ignored: it would leave a page on disk.
    static func clear() {
        do {
            try clear(in: .cachesDirectory)
        } catch {
            Logger.scan.error(
                "The document camera's pages weren't removed: \(ErrorSummary.describe(error), privacy: .public)")
        }
    }
}
