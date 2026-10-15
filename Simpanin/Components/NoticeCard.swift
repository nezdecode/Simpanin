//
//  NoticeCard.swift
//  Simpanin
//
//  Created by Inez Amanda on 14/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

/// The warm card for things that need a look: the expiry banner and the notices after opening.
struct NoticeCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .foregroundStyle(Color(.onWarning))
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.warning), in: .rect(cornerRadius: 16))
    }
}

extension View {
    func noticeCard() -> some View { modifier(NoticeCard()) }
}
