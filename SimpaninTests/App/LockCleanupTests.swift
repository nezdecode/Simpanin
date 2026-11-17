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
    /// UIKit removes a presented screen a moment after dismiss returns, so the clears wait for it.
    @Test func theLockHandlerDismissesBeforeClearing() {
        var steps: [String] = []
        var finishDismiss: (() -> Void)?
        let cleanup = LockCleanup(
            dismissPresented: { done in
                steps.append("dismiss")
                finishDismiss = done
            },
            clear: [{ steps.append("camera") }, { steps.append("shared copies") }])
        cleanup.run()
        #expect(steps == ["dismiss"])
        finishDismiss?()
        #expect(steps == ["dismiss", "camera", "shared copies"])
        // A late second call, like the fallback after a refused dismiss, clears nothing twice.
        finishDismiss?()
        #expect(steps == ["dismiss", "camera", "shared copies"])
    }

    /// The app keeps running in the background until this comes, so the files must be gone by then.
    @Test func theCompletionComesOnceAfterTheClears() {
        var steps: [String] = []
        var finishDismiss: (() -> Void)?
        let cleanup = LockCleanup(
            dismissPresented: { finishDismiss = $0 },
            clear: [{ steps.append("camera") }, { steps.append("shared copies") }])
        cleanup.run { steps.append("done") }
        #expect(steps.isEmpty)
        finishDismiss?()
        finishDismiss?()
        #expect(steps == ["camera", "shared copies", "done"])
    }
}
