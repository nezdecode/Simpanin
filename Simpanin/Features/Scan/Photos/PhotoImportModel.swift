//
//  PhotoImportModel.swift
//  Simpanin
//
//  Created by Inez Amanda on 31/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import CoreGraphics
import Foundation
import OSLog
import Observation
import PhotosUI
import SwiftUI

/// The photos picked with Tambah, loaded and decoded for Periksa data, and which screen of the photo flow
/// shows. Kept in memory only.
@MainActor @Observable
final class PhotoImportModel {
    enum Screen: Equatable {
        case picker, loading, review, ended
    }

    /// The picked files, kept until Simpan decodes them again at the stored size, and the pages shown.
    struct Picked {
        let photos: [Data]
        let pages: [CGImage]
    }

    /// A photo couldn't be loaded or decoded; the alert says so until it's closed.
    private(set) var loadFailed = false
    private(set) var screen = Screen.picker
    /// What's ticked in the picker. Nothing loads, and the flow doesn't count as started, until Tambah.
    var selection: [PhotosPickerItem] = []
    /// The photo being loaded, from 1, of how many were added.
    private(set) var loadingNumber = 0
    private(set) var loadingCount = 0

    var canAdd: Bool { !selection.isEmpty }

    private let loader: any PhotoLoading
    private let decode: @Sendable (Data) async -> CGImage?
    private let onStarted: () -> Void

    init(
        loader: any PhotoLoading, decode: @escaping @Sendable (Data) async -> CGImage? = PhotoDecoding.shown,
        onStarted: @escaping () -> Void = {}
    ) {
        self.loader = loader
        self.decode = decode
        self.onStarted = onStarted
    }

    /// Pages from an earlier pick are in Periksa data; a pick after them that fails or is cancelled keeps them.
    private var hasPages = false
    private var started = false
    private var added: [PhotosPickerItem] = []

    /// Tambah.
    func add() {
        guard canAdd else { return }
        if !started {
            started = true
            onStarted()
        }
        added = selection
        screen = .loading
    }

    /// Loads what Tambah added; from the screen's `.task`, so the lock cancels it.
    func loadAdded() async -> Picked? {
        guard screen == .loading, let picked = await load(added) else { return nil }
        added = []
        hasPages = true
        screen = .review
        return picked
    }

    /// Batal in the picker.
    func cancelPicker() {
        screen = hasPages ? .review : .ended
    }

    /// "Pilih foto lain".
    func pickAgain() {
        selection = []
        screen = .picker
    }

    /// The failed photo's alert was closed.
    func failureSeen() {
        loadFailed = false
        added = []
        screen = hasPages ? .review : .ended
    }

    /// Bumped by every load and by Batal, so a load Photos finishes later knows it's stale.
    private var generation = 0

    /// One photo at a time, in the order picked. If any can't be loaded or decoded, none is handed on.
    /// Nil also when Batal or the lock ended it: Photos may finish a load after it's cancelled.
    func load(_ items: [PhotosPickerItem]) async -> Picked? {
        generation += 1
        let run = generation
        loadFailed = false
        loadingCount = items.count
        var photos: [Data] = []
        var pages: [CGImage] = []
        for (number, item) in zip(1..., items) {
            loadingNumber = number
            let data: Data?
            do {
                data = try await loader.data(for: item)
            } catch {
                guard isCurrent(run) else { return nil }
                Logger.scan.error("Photo load failed: \(ErrorSummary.describe(error), privacy: .public)")
                loadFailed = true
                return nil
            }
            guard isCurrent(run) else { return nil }
            guard let data, let page = await decode(data) else {
                if isCurrent(run) { loadFailed = true }
                return nil
            }
            guard isCurrent(run) else { return nil }
            photos.append(data)
            pages.append(page)
        }
        return Picked(photos: photos, pages: pages)
    }

    /// Batal while loading: ends at once, without waiting for Photos.
    func cancel() {
        generation += 1
        loadFailed = false
        added = []
        screen = hasPages ? .review : .ended
    }

    /// A cancelled task is the lock removing the flow, which drops the load as Batal does.
    private func isCurrent(_ run: Int) -> Bool {
        guard run == generation else { return false }
        guard !Task.isCancelled else {
            cancel()
            return false
        }
        return true
    }
}
