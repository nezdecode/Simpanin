//
//  PhotoImportModelTests.swift
//  SimpaninTests
//
//  Created by Inez Amanda on 31/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import PhotosUI
import SwiftUI
import Synchronization
import Testing

@testable import Simpanin

/// Hands over scripted photos by item identifier. A held photo waits for `release` and, like Photos may,
/// ignores cancellation; a cancellable one waits until its task is cancelled and throws, as Photos' own
/// loader does.
nonisolated final class ScriptedPhotos: PhotoLoading {
    enum Outcome: Sendable {
        case photo(Data)
        case nothing, fails
        case held(Data)
        case cancellable
    }

    struct Failure: Error {}

    let script: [String: Outcome]
    let held = Mutex(false)
    let released: AsyncStream<Void>
    let release: AsyncStream<Void>.Continuation

    init(_ script: [String: Outcome]) {
        self.script = script
        (released, release) = AsyncStream<Void>.makeStream()
    }

    var isHolding: Bool { held.withLock { $0 } }

    func data(for item: PhotosPickerItem) async throws -> Data? {
        switch script[item.itemIdentifier ?? ""] {
        case .photo(let data): return data
        case .held(let data):
            held.withLock { $0 = true }
            for await _ in released { break }
            return data
        case .cancellable:
            held.withLock { $0 = true }
            try await Task.sleep(for: .seconds(10))
            return nil
        case .fails: throw Failure()
        case .nothing, nil: return nil
        }
    }
}

@MainActor
@Suite("Photo import")
struct PhotoImportModelTests {
    func photo(width: Int) throws -> Data {
        try SyntheticPhoto.file(try SyntheticPhoto.image(width: width, height: 100))
    }

    func items(_ ids: String...) -> [PhotosPickerItem] {
        ids.map { PhotosPickerItem(itemIdentifier: $0) }
    }

    /// Waits up to two seconds for the held photo to be asked for, never forever.
    func waitUntilHolding(_ photos: ScriptedPhotos) async throws {
        for _ in 0..<2_000 where !photos.isHolding {
            try await Task.sleep(for: .milliseconds(1))
        }
        try #require(photos.isHolding)
    }

    @Test func keepsPickedOrder() async throws {
        let first = try photo(width: 300)
        let second = try photo(width: 200)
        let photos = ScriptedPhotos(["a": .photo(first), "b": .photo(second)])
        let picked = try #require(await PhotoImportModel(loader: photos).load(items("a", "b")))
        #expect(picked.photos == [first, second])
        #expect(picked.pages.map(\.width) == [300, 200])
    }

    @Test(arguments: [ScriptedPhotos.Outcome.fails, .nothing, .photo(Data("not a photo".utf8))])
    func failsWholeImportWhenOnePhotoFails(_ outcome: ScriptedPhotos.Outcome) async throws {
        let photos = ScriptedPhotos(["a": .photo(try photo(width: 300)), "b": outcome])
        let model = PhotoImportModel(loader: photos)
        #expect(await model.load(items("a", "b")) == nil)
        #expect(model.loadFailed)
    }

    @Test func showsLoadingUntilDone() async throws {
        let photos = ScriptedPhotos(["a": .held(try photo(width: 300))])
        defer { photos.release.finish() }
        let model = PhotoImportModel(loader: photos)
        model.selection = items("a")
        model.add()
        let loading = Task { await model.loadAdded() }
        try await waitUntilHolding(photos)
        #expect(model.screen == .loading)
        #expect(model.loadingNumber == 1)
        #expect(model.loadingCount == 1)
        photos.release.yield()
        #expect(await loading.value != nil)
        #expect(model.screen == .review)
        #expect(!model.loadFailed)
    }

    /// Batal while loading ends at once; the photo Photos hands over later is dropped.
    @Test func cancelledImportKeepsNothing() async throws {
        let photos = ScriptedPhotos(["a": .held(try photo(width: 300))])
        defer { photos.release.finish() }
        let model = PhotoImportModel(loader: photos)
        let loading = Task { await model.load(items("a")) }
        try await waitUntilHolding(photos)
        model.cancel()
        #expect(!model.loadFailed)
        photos.release.yield()
        #expect(await loading.value == nil)
        #expect(!model.loadFailed)
    }

    /// A load that outlives Batal never overrides the pick made after it.
    @Test func lateLoadAfterBatalIsDropped() async throws {
        let photos = ScriptedPhotos(["slow": .held(try photo(width: 300)), "fast": .photo(try photo(width: 200))])
        defer { photos.release.finish() }
        let model = PhotoImportModel(loader: photos)
        let late = Task { await model.load(items("slow")) }
        try await waitUntilHolding(photos)
        model.cancel()
        let picked = try #require(await model.load(items("fast")))
        #expect(picked.pages.map(\.width) == [200])
        photos.release.yield()
        #expect(await late.value == nil)
        #expect(!model.loadFailed)
    }

    /// The lock removes the flow, which cancels its task; nothing loaded is handed on.
    @Test func lockDuringImportKeepsNothing() async throws {
        let photos = ScriptedPhotos(["a": .held(try photo(width: 300))])
        defer { photos.release.finish() }
        let model = PhotoImportModel(loader: photos)
        let loading = Task { await model.load(items("a")) }
        try await waitUntilHolding(photos)
        loading.cancel()
        photos.release.yield()
        #expect(await loading.value == nil)
        #expect(!model.loadFailed)
        #expect(model.screen == .ended)
    }

    /// Photos' loader throws once the lock cancels it; that's the lock, not a photo that can't be opened.
    @Test func lockDuringImportThatThrowsKeepsNothing() async throws {
        let photos = ScriptedPhotos(["a": .cancellable])
        let model = PhotoImportModel(loader: photos)
        let loading = Task { await model.load(items("a")) }
        try await waitUntilHolding(photos)
        loading.cancel()
        #expect(await loading.value == nil)
        #expect(!model.loadFailed)
        #expect(model.screen == .ended)
    }

    /// A lock while a second pick loads goes back to Periksa data, as Batal does, not to the end.
    @Test func lockDuringRePickGoesBackToReview() async throws {
        let photos = ScriptedPhotos(["a": .photo(try photo(width: 300)), "b": .cancellable])
        let model = PhotoImportModel(loader: photos)
        model.selection = items("a")
        model.add()
        #expect(await model.loadAdded() != nil)
        model.pickAgain()
        model.selection = items("b")
        model.add()
        let loading = Task { await model.loadAdded() }
        try await waitUntilHolding(photos)
        loading.cancel()
        #expect(await loading.value == nil)
        #expect(!model.loadFailed)
        #expect(model.screen == .review)
    }

    // MARK: - The flow

    /// Ticking photos is no decision yet: the flow starts, and the lock may call it dropped, only on Tambah.
    @Test func nothingStartsBeforeTambah() throws {
        var started = 0
        let model = PhotoImportModel(loader: ScriptedPhotos([:]), onStarted: { started += 1 })
        model.add()
        #expect(model.screen == .picker)
        model.selection = items("a")
        #expect(started == 0)
        #expect(model.screen == .picker)
        model.add()
        #expect(started == 1)
        #expect(model.screen == .loading)
    }

    @Test func emptySelectionEndsFlow() {
        let model = PhotoImportModel(loader: ScriptedPhotos([:]))
        model.cancelPicker()
        #expect(model.screen == .ended)
    }

    @Test func batalWhileLoadingEndsFlow() async throws {
        let photos = ScriptedPhotos(["a": .held(try photo(width: 300))])
        defer { photos.release.finish() }
        let model = PhotoImportModel(loader: photos)
        model.selection = items("a")
        model.add()
        let loading = Task { await model.loadAdded() }
        try await waitUntilHolding(photos)
        model.cancel()
        #expect(model.screen == .ended)
        photos.release.yield()
        #expect(await loading.value == nil)
    }

    @Test func firstPickFailureEndsFlow() async {
        let model = PhotoImportModel(loader: ScriptedPhotos(["a": .fails]))
        model.selection = items("a")
        model.add()
        #expect(await model.loadAdded() == nil)
        #expect(model.loadFailed)
        model.failureSeen()
        #expect(!model.loadFailed)
        #expect(model.screen == .ended)
    }

    /// The pages loaded first, and what the user typed about them, stay when the next pick fails.
    @Test func rePickKeepsPagesWhenItFails() async throws {
        var started = 0
        let photos = ScriptedPhotos(["a": .photo(try photo(width: 300)), "b": .fails])
        let model = PhotoImportModel(loader: photos, onStarted: { started += 1 })
        model.selection = items("a")
        model.add()
        #expect(await model.loadAdded()?.pages.count == 1)
        #expect(model.screen == .review)
        model.pickAgain()
        #expect(model.screen == .picker)
        #expect(model.selection.isEmpty)
        model.selection = items("b")
        model.add()
        #expect(await model.loadAdded() == nil)
        model.failureSeen()
        #expect(model.screen == .review)
        #expect(started == 1)
    }

    @Test func rePickCancelledKeepsPages() async throws {
        let photos = ScriptedPhotos(["a": .photo(try photo(width: 300)), "b": .held(try photo(width: 200))])
        defer { photos.release.finish() }
        let model = PhotoImportModel(loader: photos)
        model.selection = items("a")
        model.add()
        #expect(await model.loadAdded() != nil)
        // Batal in the picker.
        model.pickAgain()
        model.cancelPicker()
        #expect(model.screen == .review)
        // Batal while the new photos load.
        model.pickAgain()
        model.selection = items("b")
        model.add()
        let loading = Task { await model.loadAdded() }
        try await waitUntilHolding(photos)
        model.cancel()
        #expect(model.screen == .review)
        photos.release.yield()
        #expect(await loading.value == nil)
        #expect(model.screen == .review)
    }

    /// Slow iCloud photos load one by one, so the screen says which one, rather than look stuck.
    @Test func saysWhichPhotoIsLoading() async throws {
        let photos = ScriptedPhotos(["a": .photo(try photo(width: 300)), "b": .held(try photo(width: 200))])
        defer { photos.release.finish() }
        let model = PhotoImportModel(loader: photos)
        model.selection = items("a", "b")
        model.add()
        let loading = Task { await model.loadAdded() }
        try await waitUntilHolding(photos)
        #expect(model.loadingNumber == 2)
        #expect(model.loadingCount == 2)
        photos.release.yield()
        #expect(await loading.value?.pages.count == 2)
    }
}
