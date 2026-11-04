//
//  Logger+Simpanin.swift
//  Simpanin
//
//  Created by Inez Amanda on 14/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import os

extension Logger {
    /// The bundle identifier, so a separate debug build logs under its own name.
    nonisolated private static let subsystem = Bundle.main.bundleIdentifier ?? "Simpanin"

    /// Never log field values, names, numbers, keys or file contents here.
    nonisolated static let launch = Logger(subsystem: subsystem, category: "launch")
    nonisolated static let library = Logger(subsystem: subsystem, category: "library")
    nonisolated static let scan = Logger(subsystem: subsystem, category: "scan")
    nonisolated static let share = Logger(subsystem: subsystem, category: "share")
}
