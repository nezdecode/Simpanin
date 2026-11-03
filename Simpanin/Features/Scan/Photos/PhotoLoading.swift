//
//  PhotoLoading.swift
//  Simpanin
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

/// Hands over the file of a photo picked in Photos. Nil when Photos has nothing to give.
nonisolated protocol PhotoLoading: Sendable {
    func data(for item: PhotosPickerItem) async throws -> Data?
}

/// The real one: the photo as `Data`, never as a file, so no copy is left on disk.
nonisolated struct PhotosPickerLoader: PhotoLoading {
    func data(for item: PhotosPickerItem) async throws -> Data? {
        try await item.loadTransferable(type: Data.self)
    }
}
