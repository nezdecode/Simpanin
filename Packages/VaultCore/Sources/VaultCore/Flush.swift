//
//  Flush.swift
//  VaultCore
//
//  Created by Inez Amanda on 4/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

/// How the flushes before a deletion were done.
public enum FlushMethod: Sendable, Equatable {
    /// fcntl(F_FULLFSYNC): asks the drive to write its cache to permanent storage.
    case fullFsync
    /// fsync, used where F_FULLFSYNC is unavailable or rejected.
    case fsync
}

/// Flushes a file or folder to permanent storage. A protocol so tests can record flushes.
protocol IndexFlusher: Sendable {
    func flush(_ url: URL) throws -> FlushMethod
}

/// F_FULLFSYNC, falling back to fsync where it fails or does not exist.
struct FileSystemFlusher: IndexFlusher {
    /// The F_FULLFSYNC call, replaceable so tests can make it fail.
    var fullSync: @Sendable (Int32) -> Int32 = Self.fullFsync

    static let fullFsync: @Sendable (Int32) -> Int32 = { descriptor in
        #if canImport(Darwin)
            return fcntl(descriptor, F_FULLFSYNC)
        #else
            return -1
        #endif
    }

    func flush(_ url: URL) throws -> FlushMethod {
        let descriptor = open(url.path, O_RDONLY)
        guard descriptor >= 0 else { throw VaultError.flushFailed }
        defer { close(descriptor) }
        if fullSync(descriptor) != -1 { return .fullFsync }
        guard fsync(descriptor) == 0 else { throw VaultError.flushFailed }
        return .fsync
    }
}
