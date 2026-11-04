//
//  LockCleanupTests.swift
//  SimpaninTests
//
//  Created by Inez Amanda on 4/11/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Testing

@testable import Simpanin

@MainActor
@Suite("Lock cleanup")
struct LockCleanupTests {
    @Test func theLockHandlerDismissesBeforeClearing() {
        var steps: [String] = []
        let cleanup = LockCleanup(
            dismissPresented: { steps.append("dismiss") },
            clear: [{ steps.append("camera") }, { steps.append("shared copies") }])
        cleanup.run()
        #expect(steps == ["dismiss", "camera", "shared copies"])
    }
}
