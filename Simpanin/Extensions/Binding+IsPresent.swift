//
//  Binding+IsPresent.swift
//  Simpanin
//
//  Created by Inez Amanda on 15/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

extension Binding where Value == Bool {
    /// True while `optional` holds a value; setting false clears it. For alerts and dialogs
    /// that show while something is pending.
    init<Wrapped>(isPresent optional: Binding<Wrapped?>) {
        self.init(get: { optional.wrappedValue != nil }, set: { if !$0 { optional.wrappedValue = nil } })
    }
}
