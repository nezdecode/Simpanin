//
//  SharedPageSource.swift
//  Simpanin
//
//  Created by Inez Amanda on 4/11/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import LinkPresentation
import UIKit

/// One marked page for the share sheet, as a file. Its header shows the app's icon and the page count, not
/// a picture of the page, so the system never draws a page outside the app's cover.
///
/// Nonisolated: the share sheet asks for the items on a queue of its own, and a main actor check there
/// stops the app.
nonisolated final class SharedPageSource: NSObject, UIActivityItemSource, Sendable {
    let file: URL
    let pageCount: Int

    init(file: URL, pageCount: Int) {
        self.file = file
        self.pageCount = pageCount
    }

    func activityViewControllerPlaceholderItem(_ controller: UIActivityViewController) -> Any { file }

    func activityViewController(
        _ controller: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? { file }

    func activityViewController(
        _ controller: UIActivityViewController, subjectForActivityType activityType: UIActivity.ActivityType?
    ) -> String { "" }

    func activityViewControllerLinkMetadata(_ controller: UIActivityViewController) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        metadata.title = String(localized: "share.sheetTitle \(pageCount)")
        if let icon = Self.appIcon { metadata.iconProvider = NSItemProvider(object: icon) }
        return metadata
    }

    /// The home screen icon, as the build lists it.
    private static var appIcon: UIImage? {
        let icons = Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any]
        let primary = icons?["CFBundlePrimaryIcon"] as? [String: Any]
        let name = (primary?["CFBundleIconFiles"] as? [String])?.last ?? primary?["CFBundleIconName"] as? String
        return name.flatMap { UIImage(named: $0) }
    }
}
