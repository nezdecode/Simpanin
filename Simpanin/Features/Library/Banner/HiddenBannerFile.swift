//
//  HiddenBannerFile.swift
//  Simpanin
//
//  Created by Inez Amanda on 17/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import VaultCore

/// hidden-banner.json in the projection folder: kept out of backups like the projection.
nonisolated struct HiddenBannerFile: HiddenBannerStoring {
    let url: URL
    let protector: any FileProtector

    static func url(in locations: VaultLocations) -> URL {
        locations.projectionFolder.appending(path: "hidden-banner.json")
    }

    func load() throws -> HiddenBanner {
        do {
            return try JSONDecoder().decode(HiddenBanner.self, from: Data(contentsOf: url))
        } catch CocoaError.fileReadNoSuchFile {
            return HiddenBanner()
        }
    }

    /// Through a temp file renamed over the old one, so a crash never leaves half a file; the temp's
    /// name is its own, so VaultCore's cleanup of its own temp files never touches it.
    func save(_ hidden: HiddenBanner) throws {
        let temp = url.deletingLastPathComponent().appending(path: ".\(url.lastPathComponent).tmp")
        do {
            try JSONEncoder().encode(hidden).write(to: temp)
            try protector.protect(temp, as: .completeUntilFirstUserAuthentication)
            guard rename(temp.path, url.path) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        } catch {
            try? FileManager.default.removeItem(at: temp)
            throw error
        }
    }
}
