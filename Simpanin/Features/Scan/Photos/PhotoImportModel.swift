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

/// The photos picked with Tambah, loaded and decoded for Periksa data. Kept in memory only.
@MainActor @Observable
final class PhotoImportModel {
    enum State: Equatable {
        case idle, loading, failed
    }

    /// The picked files, kept until Simpan decodes them again at the stored size, and the pages shown.
    struct Picked {
        let photos: [Data]
        let pages: [CGImage]
    }

    private(set) var state = State.idle

    private let loader: any PhotoLoading
    private let decode: @Sendable (Data) async -> CGImage?

    init(loader: any PhotoLoading, decode: @escaping @Sendable (Data) async -> CGImage? = PhotoDecoding.shown) {
        self.loader = loader
        self.decode = decode
    }

    /// Bumped by every load and by Batal, so a load Photos finishes later knows it's stale.
    private var generation = 0

    /// One photo at a time, in the order picked. If any can't be loaded or decoded, none is handed on.
    /// Nil also when Batal or the lock ended it: Photos may finish a load after it's cancelled.
    func load(_ items: [PhotosPickerItem]) async -> Picked? {
        generation += 1
        let run = generation
        state = .loading
        var photos: [Data] = []
        var pages: [CGImage] = []
        for item in items {
            let data: Data?
            do {
                data = try await loader.data(for: item)
            } catch {
                guard isCurrent(run) else { return nil }
                Logger.scan.error("Photo load failed: \(ErrorSummary.describe(error), privacy: .public)")
                state = .failed
                return nil
            }
            guard isCurrent(run) else { return nil }
            guard let data, let page = await decode(data) else {
                if isCurrent(run) { state = .failed }
                return nil
            }
            guard isCurrent(run) else { return nil }
            photos.append(data)
            pages.append(page)
        }
        state = .idle
        return Picked(photos: photos, pages: pages)
    }

    /// Batal while loading: ends at once, without waiting for Photos.
    func cancel() {
        generation += 1
        state = .idle
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
