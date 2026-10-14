//
//  VaultCore.swift
//  VaultCore
//
//  Created by Inez Amanda on 4/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

// VaultCore is Simpanin's encrypted document storage. It only depends on Foundation and
// swift-crypto, so keep platform frameworks like UIKit and Security out of it.
//
// VaultStore is the only way in, split by topic into VaultStore+*.swift. Models.swift holds the
// public types, Format.swift everything written to disk, and Protocols.swift what the app
// supplies: the key store, the clock and file protection.
