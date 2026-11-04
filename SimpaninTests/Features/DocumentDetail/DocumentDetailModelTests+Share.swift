//
//  DocumentDetailModelTests+Share.swift
//  SimpaninTests
//
//  Created by Inez Amanda on 4/11/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Testing

@testable import Simpanin

/// Bagikan salinan, as the document screen offers it.
extension DocumentDetailModelTests {
    /// The share sheet covers the screen, as the viewer does.
    @Test func openingBagikanMasksTheNumber() async throws {
        let detail = try await loaded()
        detail.toggleNumber()
        #expect(detail.numberShown)
        #expect(detail.canShare)
        detail.shareOpened()
        #expect(!detail.numberShown)
    }

    @Test func aDeletedDocumentOrOneWithoutPagesHasNoBagikan() async throws {
        #expect(!(try await loadedDeleted()).canShare)
        let pageless = try await model(pages: [])
        await pageless.load()
        #expect(!pageless.canShare)
    }
}
