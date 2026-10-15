//
//  NoticeList.swift
//  Simpanin
//
//  Created by Inez Amanda on 14/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

/// The one-time notices from opening, then the full-disk banner, each dismissed with "Oke".
struct NoticeList: View {
    let notices: Set<VaultNotice>
    let onDismiss: (VaultNotice) -> Void

    private let order: [VaultNotice] = [.recoveredFromPages, .newestChangeMayBeLost, .repairWaitingForSpace]

    var body: some View {
        ForEach(order, id: \.self) { notice in
            if notices.contains(notice) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: notice == .repairWaitingForSpace ? "externaldrive" : "info.circle")
                    VStack(alignment: .leading, spacing: 8) {
                        Text(notice.message)
                        Button {
                            onDismiss(notice)
                        } label: {
                            Text(ScreenText.okay).fontWeight(.semibold)
                        }
                    }
                }
                .noticeCard()
            }
        }
    }
}
