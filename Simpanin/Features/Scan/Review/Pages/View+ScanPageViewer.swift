//
//  View+ScanPageViewer.swift
//  Simpanin
//
//  Created by Inez Amanda on 30/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

extension View {
    /// Periksa data's pages full screen, with the fields to check under them. On the screen, not the pages
    /// section: in a Form, a Section's modifiers go to its rows.
    func scanPageViewer(
        isPresented: Binding<Bool>, page: Binding<Int>, review: ReviewModel, transition: Namespace.ID
    ) -> some View {
        fullScreenCover(isPresented: isPresented) {
            // Nothing under the viewer follows its page, so there's nothing to hand back.
            PageViewer(
                count: review.pages.count, current: page, thumbnail: review.thumbnail,
                image: review.viewerPage, onSettle: {}
            )
            .checkedFieldsBar(review.checkedFields)
            // Also what lets a swipe down close it.
            .navigationTransition(.zoom(sourceID: page.wrappedValue, in: transition))
        }
    }
}
