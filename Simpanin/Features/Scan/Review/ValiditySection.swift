//
//  ValiditySection.swift
//  Simpanin
//
//  Created by Inez Amanda on 27/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI
import VaultCore

/// Periksa data's Masa berlaku: "Seumur hidup" on a KTP, the expiry date on a type that prints one, and
/// nothing on the others.
struct ValiditySection: View {
    let type: DocumentType
    let hasExpiry: Bool
    let expiry: CalendarDate?
    /// The mark under the date, already worded.
    let note: LocalizedStringResource?
    let onChange: (CalendarDate?) -> Void
    /// Opens the calendar for an expiry not read yet.
    let onPick: () -> Void

    var body: some View {
        if type == .ktp {
            Section {
                LabeledContent {
                    Text("review.forLife")
                } label: {
                    Text("review.validFor")
                }
            }
        } else if hasExpiry {
            Section {
                if let expiry = expiry, let shown = expiry.utcDate {
                    DatePicker(
                        selection: Binding(get: { shown }, set: { onChange(CalendarDate(utc: $0)) }),
                        displayedComponents: .date
                    ) {
                        expiryLabel
                    }
                    // Expiry dates are calendar days in UTC, so no time zone moves them.
                    .environment(\.timeZone, .gmt)
                    .accessibilityIdentifier("review.expiry")
                } else {
                    // Never shown as today: an empty expiry has to be seen, not saved quietly as none. The
                    // calendar sets nothing until Pilih, so opening it can't fill in a date by itself.
                    Button {
                        onPick()
                    } label: {
                        LabeledContent {
                            HStack(spacing: 6) {
                                Text("review.expiryMissing")
                                DisclosureChevron()
                            }
                        } label: {
                            expiryLabel
                        }
                    }
                    .accessibilityIdentifier("review.expiry")
                }
            } footer: {
                // The date printed on an STNK is its five-year validity; the one that matters is the tax.
                if type == .stnk { Text("review.taxHint") }
            }
        }
    }

    /// An STNK's date is its yearly tax; every other type's is its validity.
    static func title(for type: DocumentType) -> LocalizedStringResource {
        type == .stnk ? "review.taxValidUntil" : "review.validUntil"
    }

    private var expiryLabel: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Self.title(for: type)).foregroundStyle(Color.primary)
            if let note { WarningText(note) }
        }
    }
}
