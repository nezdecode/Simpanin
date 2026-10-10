import Foundation

/// A vault that "Mulai vault baru" moved aside, as listed for "Data lama" in Settings.
public struct QuarantinedVault: Sendable, Equatable {
    public let vaultID: VaultID
    public let folder: URL
    public let sizeInBytes: Int64
}

/// Everything in the quarantine folder. Unreadable folders are listed, never touched.
public struct QuarantineListing: Sendable, Equatable {
    public var vaults: [QuarantinedVault]
    public var unreadableFolders: [URL]
}

extension VaultStore {
    /// Locks the store and moves the vault folder, unchanged, into `quarantineDirectory` as
    /// `yyyyMMdd-HHmmss` in UTC (-2, -3 if taken). Deletes nothing; nil if there was no vault.
    @discardableResult
    public func quarantineVault(to quarantineDirectory: URL) async throws -> URL? {
        if let openTask { _ = try? await openTask.value }
        lock()
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: root.path) else { return nil }
        try fileManager.createDirectory(at: quarantineDirectory, withIntermediateDirectories: true)
        let destination = quarantineDestination(in: quarantineDirectory)
        try fileManager.moveItem(at: root, to: destination)
        return destination
    }

    /// Oldest first. Works while locked.
    public func quarantinedVaults(in quarantineDirectory: URL) throws -> QuarantineListing {
        var listing = QuarantineListing(vaults: [], unreadableFolders: [])
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: quarantineDirectory.path) else { return listing }
        let folders = try fileManager.contentsOfDirectory(
            at: quarantineDirectory, includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
        for folder in folders {
            if let header = try? readHeader(at: folder.appending(path: "vault.json")) {
                listing.vaults.append(
                    QuarantinedVault(
                        vaultID: header.vaultId, folder: folder,
                        sizeInBytes: try folderSize(folder)))
            } else {
                listing.unreadableFolders.append(folder)
            }
        }
        return listing
    }

    /// Deletes the Keychain item, then the folder. Refuses a mismatched or in-use vault; if
    /// the key can't be deleted, the folder stays so the user can try again.
    public func deleteQuarantinedVault(_ vault: QuarantinedVault) async throws {
        guard let header = try? readHeader(at: vault.folder.appending(path: "vault.json")),
            header.vaultId == vault.vaultID
        else {
            throw VaultError.quarantineUnreadable
        }
        let liveID = state?.header.vaultId ?? (try? readHeader(at: headerURL))?.vaultId
        guard liveID != vault.vaultID,
            vault.folder.standardizedFileURL.path != root.standardizedFileURL.path
        else {
            throw VaultError.quarantineInUse
        }
        do {
            try await keyStore.deleteVaultKey(for: vault.vaultID)
        } catch KeyStoreError.itemNotFound {
            // Already gone: nothing left to delete in the key store.
        } catch {
            throw Self.unavailable(error)
        }
        try FileManager.default.removeItem(at: vault.folder)
    }

    private func folderSize(_ folder: URL) throws -> Int64 {
        var total: Int64 = 0
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        if let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys) {
            for case let url as URL in files {
                let values = try url.resourceValues(forKeys: Set(keys))
                if values.isRegularFile == true { total += Int64(values.fileSize ?? 0) }
            }
        }
        return total
    }

    private func quarantineDestination(in directory: URL) -> URL {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let time = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: now())
        let base = String(
            format: "%04d%02d%02d-%02d%02d%02d",
            time.year ?? 0, time.month ?? 0, time.day ?? 0, time.hour ?? 0, time.minute ?? 0, time.second ?? 0)
        var name = base
        var suffix = 2
        while FileManager.default.fileExists(atPath: directory.appending(path: name).path) {
            name = "\(base)-\(suffix)"
            suffix += 1
        }
        return directory.appending(path: name, directoryHint: .isDirectory)
    }
}
