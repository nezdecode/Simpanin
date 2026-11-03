//
//  ScanSource.swift
//  Simpanin
//
//  Created by Inez Amanda on 3/11/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

/// Where a document being added comes from, so a lock that drops it says what happened to it.
nonisolated enum ScanSource: Identifiable, Sendable {
    case camera, photos

    var id: Self { self }
}
