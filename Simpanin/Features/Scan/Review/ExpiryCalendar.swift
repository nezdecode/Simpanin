//
//  ExpiryCalendar.swift
//  Simpanin
//
//  Created by Inez Amanda on 17/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI
import VaultCore

/// The calendar for an expiry that wasn't read. It starts on today but sets nothing until Pilih.
struct ExpiryCalendar: View {
    let title: LocalizedStringResource
    let onPick: (CalendarDate?) -> Void
    @State private var draft = CalendarDate.today.utcDate ?? .now
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            DatePicker(selection: $draft, displayedComponents: .date) {
                Text(title)
            }
            .datePickerStyle(.graphical)
            // Expiry dates are calendar days in UTC, so no time zone moves them.
            .environment(\.timeZone, .gmt)
            .padding(.horizontal)
            .navigationTitle(Text(title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text(ScreenText.cancel)
                    }
                    .accessibilityIdentifier("review.expiryCancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onPick(CalendarDate(utc: draft))
                        dismiss()
                    } label: {
                        Text("review.pickDate")
                    }
                    .accessibilityIdentifier("review.expiryPick")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
