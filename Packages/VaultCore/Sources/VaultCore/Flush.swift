import Foundation

/// Which call made the new index durable before step 3 deleted files.
public enum FlushMethod: Sendable, Equatable {
    /// fcntl(F_FULLFSYNC): asks the drive to write its cache to permanent storage.
    case fullFsync
    /// fsync, used where F_FULLFSYNC is unavailable or rejected.
    case fsync
}

/// Flushes a written file to permanent storage. A seam so tests can observe when the store
/// flushes; the store uses `FileSystemFlusher`.
protocol IndexFlusher: Sendable {
    func flush(_ url: URL) throws -> FlushMethod
}

/// F_FULLFSYNC, falling back to fsync when F_FULLFSYNC fails (for example on a file system
/// that does not support it) or does not exist on the platform.
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
