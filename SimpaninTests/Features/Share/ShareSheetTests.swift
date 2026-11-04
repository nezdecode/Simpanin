//
//  ShareSheetTests.swift
//  SimpaninTests
//
//  Created by Inez Amanda on 4/11/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import LinkPresentation
import Testing
import UIKit

@testable import Simpanin

@MainActor
@Suite("Share sheet")
struct ShareSheetTests {
    let files = [
        URL(filePath: "/tmp/SharedCopies/a/Simpanin 4 Nov 2026 halaman 1.jpg"),
        URL(filePath: "/tmp/SharedCopies/a/Simpanin 4 Nov 2026 halaman 2.jpg"),
    ]

    @Test func theItemSourceGivesNoPageImage() throws {
        let controller = ActivitySharePresenter.controller(for: files)
        let source = SharedPageSource(file: files[0], pageCount: 2)
        let metadata = try #require(source.activityViewControllerLinkMetadata(controller))
        #expect(metadata.imageProvider == nil)
        #expect(metadata.originalURL == nil && metadata.url == nil)
        #expect(metadata.title == String(localized: "share.sheetTitle \(2)"))
    }

    @Test func theShareCarriesNoSubjectOrText() {
        let controller = ActivitySharePresenter.controller(for: files)
        for (index, file) in files.enumerated() {
            let source = SharedPageSource(file: file, pageCount: files.count)
            #expect(source.activityViewController(controller, subjectForActivityType: .mail).isEmpty)
            #expect(source.activityViewController(controller, itemForActivityType: .message) as? URL == files[index])
            #expect(source.activityViewControllerPlaceholderItem(controller) as? URL == files[index])
        }
    }

    @Test func theExcludedActivitiesAreSaveToPhotosCopyAndAssignToContact() {
        let expected: Set<UIActivity.ActivityType> = [.saveToCameraRoll, .copyToPasteboard, .assignToContact]
        #expect(Set(ActivitySharePresenter.excludedActivityTypes) == expected)
        #expect(Set(ActivitySharePresenter.controller(for: files).excludedActivityTypes ?? []) == expected)
    }
}
