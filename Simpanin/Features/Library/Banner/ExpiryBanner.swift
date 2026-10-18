//
//  ExpiryBanner.swift
//  Simpanin
//
//  Created by Inez Amanda on 14/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI
import VaultCore

/// The document nearest its expiry, or past it, and how many others need a look. "Jangan tampilkan di
/// sini" takes one out, from the … menu, a long press or VoiceOver.
struct ExpiryBanner: View {
    let documents: [VaultCore.Document]
    let today: CalendarDate
    let onHide: (VaultCore.Document) -> Void

    var body: some View {
        let attention = ExpiryText.bannerOrder(
            documents.map { ExpiryText.BannerCandidate(type: $0.type, expiry: $0.expiry, createdAt: $0.createdAt) },
            today: today)
        if let first = attention.first {
            let document = documents[first]
            HStack(alignment: .top, spacing: 12) {
                HStack(spacing: 12) {
                    IconBadge(systemImage: "clock", tint: Color(.onWarning), background: Color(.warningIcon))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(DocumentStyle.name(document.type)).font(.headline)
                        Text(ExpiryText.text(type: document.type, expiry: document.expiry, today: today))
                        if attention.count > 1 {
                            Text("banner.more \(attention.count - 1)").font(.subheadline)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                .accessibilityAction(named: Text("banner.hide")) { onHide(document) }
                .accessibilityIdentifier("banner")
                Menu {
                    hideButton(document)
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(.rect)
                }
                .accessibilityLabel(Text("banner.options"))
                .accessibilityIdentifier("banner.menu")
            }
            .noticeCard()
            .contextMenu { hideButton(document) }
        }
    }

    private func hideButton(_ document: VaultCore.Document) -> some View {
        Button {
            onHide(document)
        } label: {
            Label {
                Text("banner.hide")
            } icon: {
                Image(systemName: "eye.slash")
            }
        }
    }
}
