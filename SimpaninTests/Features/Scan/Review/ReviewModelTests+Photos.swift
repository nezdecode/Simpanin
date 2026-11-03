//
//  ReviewModelTests+Photos.swift
//  SimpaninTests
//
//  Created by Inez Amanda on 31/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import CoreGraphics
import Foundation
import ImageIO
import Synchronization
import Testing
import VaultCore

@testable import Simpanin

/// Saving picked photos: the vault gets the photos the user checked, decoded again at the stored size.
extension ReviewModelTests {
    func photoFiles(_ sizes: [(width: Int, height: Int)]) throws -> [Data] {
        try sizes.map { try SyntheticPhoto.file(try SyntheticPhoto.image(width: $0.width, height: $0.height)) }
    }

    /// Small shown pages, as the checks need none larger; `shown` can differ from the photos' count.
    func loadPhotos(_ originals: [Data], shown: Int? = nil, into review: ReviewModel) throws {
        let pages = try (0..<(shown ?? originals.count)).map { _ in try page() }
        review.load(
            Self.ktp, pages: pages, thumbnails: PageThumbnail.thumbnails(of: pages), saving: .photos(originals))
    }

    func pixelSize(of page: Data) throws -> [Int] {
        let source = try #require(CGImageSourceCreateWithData(page as CFData, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        return [
            try #require(properties[kCGImagePropertyPixelWidth] as? Int),
            try #require(properties[kCGImagePropertyPixelHeight] as? Int),
        ]
    }

    @Test func savesStoredSizePages() async throws {
        let store = FakeDocuments()
        let review = model(store)
        try loadPhotos(try photoFiles([(6_500, 1_000)]), into: review)
        #expect(await review.save())
        let saved = try #require(await store.createdPages.first)
        #expect(try pixelSize(of: try #require(saved.first)) == [PhotoDecoding.storedPixelSize, 923])
    }

    @Test func failedStoredDecodeSavesNothing() async throws {
        let store = FakeDocuments()
        let review = model(store)
        try loadPhotos([try photoFiles([(400, 300)])[0], Data("not a photo".utf8)], into: review)
        #expect(await !review.save())
        #expect(review.saveError == .saveFailed)
        #expect(await store.createdPages.isEmpty)
    }

    /// A document never stores pages other than the ones the user checked, in the order they were shown.
    @Test func storedPagesMatchShownCountAndOrder() async throws {
        let store = FakeDocuments()
        let review = model(store)
        try loadPhotos(try photoFiles([(200, 100), (100, 300)]), into: review)
        #expect(await review.save())
        let saved = try #require(await store.createdPages.first)
        #expect(try saved.map(pixelSize) == [[200, 100], [100, 300]])

        let other = FakeDocuments()
        let mismatched = model(other)
        try loadPhotos(try photoFiles([(200, 100)]), shown: 2, into: mismatched)
        #expect(await !mismatched.save())
        #expect(await other.createdPages.isEmpty)
    }

    /// A new pick replaces the photos with the pages, and a rescan with the camera saves its own pages.
    @Test func aNewPickNeverSavesTheOldPhotos() async throws {
        let store = FakeDocuments()
        let review = model(store)
        try loadPhotos(try photoFiles([(200, 100)]), into: review)
        try loadPhotos(try photoFiles([(100, 300)]), into: review)
        #expect(await review.save())
        #expect(try await store.createdPages.first.map { try $0.map(pixelSize) } == [[100, 300]])

        let camera = FakeDocuments()
        let rescanned = model(camera)
        try loadPhotos(try photoFiles([(200, 100)]), into: rescanned)
        rescanned.loadScan(Self.ktp, pages: [try page()])
        #expect(await rescanned.save())
        #expect(await camera.createdPages.first == [Data([1])])
    }

    /// Locking the vault removes Periksa data and cancels its save. A vault opened again before the decode
    /// ends must not get the document the notice says was dropped, and the lock isn't a page that failed.
    @Test func lockDuringStoredDecodeSavesNothing() async throws {
        let store = FakeDocuments()
        let started = Mutex(false)
        let (released, release) = AsyncStream<Void>.makeStream()
        // However the test ends, the decode it holds open finishes.
        defer { release.finish() }
        let review = model(
            store,
            storePhotos: { photos in
                started.withLock { $0 = true }
                for await _ in released { break }
                // As the real decode does once cancelled.
                return Task.isCancelled ? nil : photos.map { _ in Data([1]) }
            })
        try loadPhotos(try photoFiles([(200, 100)]), into: review)
        let saving = Task { await review.save() }
        // The decode runs off the main actor; wait up to two seconds for it to start, never forever.
        for _ in 0..<2_000 where !started.withLock({ $0 }) {
            try await Task.sleep(for: .milliseconds(1))
        }
        try #require(started.withLock { $0 })
        saving.cancel()
        release.yield()
        #expect(await !saving.value)
        #expect(await store.createdPages.isEmpty)
        #expect(review.saveError == nil)
    }
}
