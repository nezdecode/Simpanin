//
//  ReviewModelTests+Saving.swift
//  SimpaninTests
//
//  Created by Inez Amanda on 17/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import CoreGraphics
import Foundation
import Parsers
import Synchronization
import Testing
import VaultCore

@testable import Simpanin

/// What a save stores, and what it never stores.
extension ReviewModelTests {
    /// Encoding a few full-size pages takes long enough to freeze the screen, so it runs off the main actor.
    @Test func pagesAreEncodedOffTheMainActor() async throws {
        let review = model(encode: { _ in Thread.isMainThread ? nil : Data([1]) })
        review.load(Self.ktp, pages: [try page()])
        #expect(await review.save())
    }

    /// What's saved is what the screen showed when Simpan was tapped, even if something changes while
    /// the pages are being encoded.
    @Test func aSaveKeepsWhatWasShownWhenItStarted() async throws {
        let store = FakeDocuments()
        let started = Mutex(false)
        let release = DispatchSemaphore(value: 0)
        let review = model(
            store,
            encode: { _ in
                started.withLock { $0 = true }
                _ = release.wait(timeout: .now() + 5)
                return Data([1])
            })
        review.load(Self.ktp, pages: [try page()])
        let saving = Task { await review.save() }
        // The encode runs off the main actor; wait up to two seconds for it to start, never forever.
        for _ in 0..<2_000 where !started.withLock({ $0 }) {
            try await Task.sleep(for: .milliseconds(1))
        }
        let encoding = started.withLock { $0 }
        review.type = .simC
        review.label = "Later"
        release.signal()
        try #require(encoding)
        #expect(await saving.value)
        let document = try #require(try await store.documents().first)
        #expect(document.type == .ktp)
        #expect(document.label == nil)
    }

    /// The last page failing is as bad as the first: the document is saved with every page or not at all.
    @Test func aLastPageThatCantBeEncodedSavesNothing() async throws {
        let store = FakeDocuments()
        let review = model(store, encode: { $0.width == 3 ? nil : Data([1]) })
        review.load(Self.ktp, pages: [try page(), try page(width: 3)])
        #expect(await !review.save())
        #expect(review.saveError == .saveFailed)
        #expect(await store.created.isEmpty)
    }

    @Test func aSIMKeepsItsExpiry() async throws {
        let store = FakeDocuments()
        let review = model(store)
        review.load(Self.sim, pages: [try page()])
        #expect(await review.save())
        #expect(try await store.documents().first?.expiry == CalendarDate(year: 2027, month: 1, day: 4))
    }

    /// An expiry read while it was a SIM doesn't follow it when the user makes it a KTP.
    @Test func aSIMChangedToAKTPSavesNoExpiry() async throws {
        let store = FakeDocuments()
        let review = model(store)
        review.load(Self.sim, pages: [try page()])
        review.type = .ktp
        #expect(await review.save())
        #expect(try await store.documents().first?.expiry == nil)
    }

    @Test func aLabelOfOnlySpacesIsNoLabel() async throws {
        let store = FakeDocuments()
        let review = model(store)
        review.load(Self.ktp, pages: [try page()])
        review.label = "   "
        #expect(await review.save())
        #expect(try await store.documents().first?.label == nil)
    }
}
