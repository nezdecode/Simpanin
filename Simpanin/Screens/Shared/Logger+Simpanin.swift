//
//  Logger+Simpanin.swift
//  Simpanin
//
//  Created by Inez Amanda on 15/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import os

extension Logger {
    /// Never log field values, names, numbers, keys or file contents here.
    nonisolated static let launch = Logger(subsystem: "com.inez.Simpanin", category: "launch")
    nonisolated static let library = Logger(subsystem: "com.inez.Simpanin", category: "library")
}
