//
//  AutoLock.swift
//  Simpanin
//
//  Created by Inez Amanda on 15/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

/// "Kunci otomatis": how long the vault may stay open in the background. Five minutes at most,
/// because a longer time makes the lock weaker.
nonisolated enum AutoLock: String, CaseIterable, Sendable {
    case immediately, oneMinute, fiveMinutes

    private static let key = "autoLock"

    var seconds: TimeInterval {
        switch self {
        case .immediately: 0
        case .oneMinute: 60
        case .fiveMinutes: 300
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .immediately: "autoLock.immediately"
        case .oneMinute: "autoLock.oneMinute"
        case .fiveMinutes: "autoLock.fiveMinutes"
        }
    }

    static func stored(in defaults: UserDefaults = .standard) -> AutoLock {
        defaults.string(forKey: key).flatMap(AutoLock.init(rawValue:)) ?? .oneMinute
    }

    func store(in defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.key)
    }
}
