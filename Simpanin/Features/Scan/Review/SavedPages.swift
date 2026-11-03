//
//  SavedPages.swift
//  Simpanin
//
//  Created by Inez Amanda on 31/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import CoreGraphics
import Foundation

/// Where the pages sealed at Simpan come from: the scan's pages as shown, or the picked photos, decoded
/// again from their files at a larger size than shown.
nonisolated enum SavedPages: Sendable {
    case shownPages
    case photos([Data])

    /// What's sealed for `shown`, one for each page and in the same order, or nil: a page that can't be
    /// prepared, or photos that aren't the pages shown, is never saved in part.
    func encoded(
        _ shown: [CGImage], encode: @Sendable (CGImage) -> Data?,
        storePhotos: @Sendable ([Data]) async -> [Data]?
    ) async -> [Data]? {
        let encoded: [Data]?
        switch self {
        case .shownPages: encoded = await Self.encoded(shown, with: encode)
        case .photos(let photos): encoded = photos.count == shown.count ? await storePhotos(photos) : nil
        }
        return encoded?.count == shown.count ? encoded : nil
    }

    /// Off the main actor: a few full-size pages take long enough to freeze the screen.
    @concurrent
    private static func encoded(_ pages: [CGImage], with encode: @Sendable (CGImage) -> Data?) async -> [Data] {
        pages.compactMap(encode)
    }
}
