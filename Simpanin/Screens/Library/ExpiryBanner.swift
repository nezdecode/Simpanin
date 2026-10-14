//
//  ExpiryBanner.swift
//  Simpanin
//
//  Created by Inez Amanda on 15/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI
import VaultCore

/// The document that expires soonest, or already has. Others that need attention are counted.
struct ExpiryBanner: View {
    let documents: [Document]
    let today: CalendarDate

    var body: some View {
        let attention = ExpiryText.needsAttention(documents.map(\.expiry), today: today)
        if let first = attention.first {
            let document = documents[first]
            HStack(spacing: 12) {
                IconBadge(symbol: "clock", tint: Color(.onWarning), background: Color(.warningIcon))
                VStack(alignment: .leading, spacing: 2) {
                    Text(DocumentStyle.name(document.type)).font(.headline)
                    Text(ExpiryText.text(type: document.type, expiry: document.expiry, today: today))
                    if attention.count > 1 {
                        Text("banner.more \(attention.count - 1)").font(.subheadline)
                    }
                }
            }
            .noticeCard()
            .accessibilityElement(children: .combine)
        }
    }
}
