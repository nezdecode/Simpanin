//
//  OutOfSpaceTests.swift
//  VaultCore
//
//  Created by Inez Amanda on 4/11/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import Testing
import VaultCore

/// The app writes shared copies itself and must call a full disk what VaultCore calls one, so the check is
/// public. Not `@testable`: this file only compiles while it is.
@Suite("Out of space")
struct OutOfSpaceTests {
    @Test func aFullDiskIsKnownInEveryForm() {
        let posix = NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC))
        #expect(VaultStore.isOutOfSpace(CocoaError(.fileWriteOutOfSpace)))
        #expect(VaultStore.isOutOfSpace(posix))
        #expect(
            VaultStore.isOutOfSpace(
                NSError(domain: NSCocoaErrorDomain, code: 512, userInfo: [NSUnderlyingErrorKey: posix])))
    }

    @Test func otherErrorsAreNotAFullDisk() {
        #expect(!VaultStore.isOutOfSpace(CocoaError(.fileWriteNoPermission)))
        #expect(!VaultStore.isOutOfSpace(NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES))))
        #expect(!VaultStore.isOutOfSpace(VaultError.locked))
    }
}
