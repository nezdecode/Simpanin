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
import Synchronization
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

    /// The screen goes between the last write and the share sheet, without its task being cancelled first.
    @Test func aScreenLeftAfterTheLastWritePresentsNothing() async throws {
        let leave = Mutex<(@MainActor @Sendable () -> Void)?>(nil)
        let writeThenLeave: SharedCopies.Write = { data, url in
            try SharedCopies.writeComplete(data, url)
            let action = leave.withLock { $0 }
            DispatchQueue.main.sync { MainActor.assumeIsolated { action?() } }
        }
        let share = try await model(pages: [Self.page()], writeFile: writeThenLeave)
        leave.withLock { $0 = { share.screenLeft() } }
        await share.share()
        #expect(presenter.presented.isEmpty)
        #expect(leftFiles().isEmpty)
        #expect(share.phase == .closed)
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
        let counts = Counts()
        let share = try await model(counts: counts)
        await share.share()
        let first = try #require(presenter.presented.first)
        // No completion ever comes for the first sheet.
        await share.share()
        #expect(presenter.presented.count == 2)
        // The first sheet is over, so a lock now isn't told as a stopped share of it.
        #expect(counts.ended == 1)
        #expect(counts.shown == 2)
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

    /// The decrypted page 1 and its marked copy go with the screen, not when SwiftUI frees the model.
    @Test func aScreenLeftLetsThePreviewGo() async throws {
        let share = try await model()
        await share.loadPreview()
        #expect(share.markedPreview != nil)
        share.screenLeft()
        #expect(share.markedPreview == nil)
        if case .shown = share.preview { Issue.record("The decrypted preview is still held") }
    }

    /// Page 1 read just after the screen went is dropped, not kept.
    @Test func aPreviewReadAfterTheScreenLeftIsDropped() async throws {
        let share = try await model()
        await store.gateNextPageRead()
        let loading = Task { await share.loadPreview() }
        #expect(await store.waitUntilReadingPage())
        share.screenLeft()
        await store.releasePageRead()
        await loading.value
        #expect(share.markedPreview == nil)
        if case .shown = share.preview { Issue.record("A preview was kept after the screen left") }
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
