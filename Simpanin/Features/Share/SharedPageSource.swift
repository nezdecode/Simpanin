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
        metadata.iconProvider = NSItemProvider(object: Self.icon)
        return metadata
    }

    /// The lock cover's shield, drawn here: the home screen icon can't be read from the bundle on a device.
    private static var icon: UIImage {
        let size = CGSize(width: 120, height: 120)
        return UIGraphicsImageRenderer(size: size).image { _ in
            UIColor(resource: .lockIconBackground).setFill()
            UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 30).fill()
            let configuration = UIImage.SymbolConfiguration(pointSize: 60, weight: .regular)
            guard
                let shield = UIImage(systemName: "lock.shield", withConfiguration: configuration)?
                    .withTintColor(UIColor(resource: .lockIcon), renderingMode: .alwaysOriginal)
            else { return }
            shield.draw(
                at: CGPoint(x: (size.width - shield.size.width) / 2, y: (size.height - shield.size.height) / 2))
        }
    }
}
