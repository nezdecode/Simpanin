//
//  CheckReason.swift
//  Parsers
//
//  Created by Inez Amanda on 19/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

/// Why a value is marked "Periksa lagi". The order is the priority: a value can have several reasons,
/// and the first case is the one shown. The raw values name the app's texts, so they never change.
public enum CheckReason: String, Sendable, CaseIterable, Comparable {
    /// The card shows signs of both SIM layouts, so nothing on it can be trusted.
    case mixedLayout
    case impossibleDate
    /// The NIK, or a new SIM's number, holds a birth date that the printed one doesn't match.
    case disagreesWithBirthDate
    case sexDisagrees
    case implausibleExpiry
    /// 16 digits whose birth date part can't be a date.
    case noDateInNumber
    case lookalike
    case oddCharacters
    case severalNumbers
    case severalDates
    case classUnclear
    /// No parser knew the text. Set by the review screen, which is where a scan without a result goes.
    case noDocumentRecognized
    case notFound
    case readFromAnotherLine
    /// An expiry read without a birth date, so it couldn't be told apart from it.
    case expiryUnconfirmed
    case mayContinue

    // A raw-value enum gets no synthesised `<`, so the order of the cases is the rank.
    public static func < (lhs: CheckReason, rhs: CheckReason) -> Bool {
        allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
    }
}
