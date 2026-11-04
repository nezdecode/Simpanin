//
//  ShareModelTests+Lock.swift
//  SimpaninTests
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

@testable import Simpanin

/// A lock, Batal and closing the document can come at any point while the copies are made.
extension ShareModelTests {
    @Test func aLockCancelsRenderingAndSharesNothing() async throws {
        let share = try await model(pages: [Self.page(), Self.page(), Self.page()])
        await store.gateNextPageRead()
        let task = Task { await share.share() }
        #expect(await store.waitUntilReadingPage())
        await store.lock()
        await store.releasePageRead()
        await task.value
        #expect(presenter.presented.isEmpty)
        #expect(share.problem == nil)
        #expect(leftFiles().isEmpty)
    }

    @Test func aLockAfterTheLastReadLeavesNoFileAndPresentsNothing() async throws {
        let share = try await model(pages: [Self.page()])
        await store.gateNextPageRead()
        let task = Task { await share.share() }
        #expect(await store.waitUntilReadingPage())
        // The lock dismisses the sheet, which cancels its task and leaves the screen.
        task.cancel()
        share.screenLeft()
        await store.releasePageRead()
        await task.value
        #expect(presenter.presented.isEmpty)
        #expect(leftFiles().isEmpty)
    }

    @Test func batalWhileRenderingLeavesNoFile() async throws {
        let share = try await model(pages: [Self.page(), Self.page(), Self.page()])
        await share.share()
        presenter.close(taken: false)
        await store.gateNextPageRead()
        let task = Task { await share.share() }
        #expect(await store.waitUntilReadingPage())
        task.cancel()
        await store.releasePageRead()
        await task.value
        #expect(presenter.presented.count == 1)
        #expect(leftFiles().isEmpty)
        #expect(share.phase == .editing)
    }

    @Test func aSecondTapWhileRenderingStartsNothing() async throws {
        let share = try await model()
        await store.gateNextPageRead()
        let first = Task { await share.share() }
        #expect(await store.waitUntilReadingPage())
        #expect(share.phase == .preparing(page: 1, count: 2))
        await share.share()
        #expect(await store.pageReads.count == 1)
        await store.releasePageRead()
        await first.value
        #expect(presenter.presented.count == 1)
    }

    @Test func aShareDismissedWithoutCompletionDoesNotBlockTheNext() async throws {
        let share = try await model()
        await share.share()
        let first = try #require(presenter.presented.first)
        // No completion ever comes for the first sheet.
        await share.share()
        #expect(presenter.presented.count == 2)
        #expect(!first.contains { FileManager.default.fileExists(atPath: $0.path) })
        #expect(leftFiles().count == 2)
    }

    @Test func aCompletionAfterTheLockDeletesNothingTwiceAndReportsNothing() async throws {
        let counts = Counts()
        let share = try await model(counts: counts)
        await share.share()
        share.screenLeft()
        #expect(leftFiles().isEmpty)
        #expect(counts.ended == 1)
        presenter.close(taken: true)
        #expect(counts.ended == 1)
        #expect(share.problem == nil)
    }

    @Test func closingTheDocumentWhileSharingLeavesNoFile() async throws {
        let share = try await model()
        await share.share()
        #expect(leftFiles().count == 2)
        share.screenLeft()
        #expect(leftFiles().isEmpty)
        #expect(share.phase == .closed)
    }
}
