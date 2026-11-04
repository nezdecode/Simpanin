//
//  SharedCopies.swift
//  Simpanin
//
//  Created by Inez Amanda on 4/11/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import CoreGraphics
import Foundation
import ImageIO
import OSLog
import UniformTypeIdentifiers
import VaultCore

/// The marked copies handed to the share sheet: the only decrypted pages that ever touch the disk. Each share
/// gets its own folder in tmp, at class Complete before anything is written into it.
nonisolated struct SharedCopies: Sendable {
    typealias Write = @Sendable (Data, URL) throws -> Void

    static let folderName = "SharedCopies"
    /// The share sheet copies in-memory items into folders named like this in our tmp, at
    /// CompleteUntilFirstUserAuthentication, and never removes them. Apple's internal name, so it's checked
    /// again after every iOS update.
    static let shareSheetPrefix = ".com.apple.ShareSheet"
    static let jpegQuality = 0.85

    /// Written with its class from the start, never at tmp's default first.
    static let writeComplete: Write = { data, url in
        try data.write(to: url, options: [.completeFileProtection, .withoutOverwriting])
    }

    let temporary: URL
    let protector: any FileProtector
    let writeFile: Write

    init(
        temporary: URL = .temporaryDirectory, protector: any FileProtector = DataProtectionFileProtector(),
        writeFile: @escaping Write = SharedCopies.writeComplete
    ) {
        self.temporary = temporary
        self.protector = protector
        self.writeFile = writeFile
    }

    // swiftlint:disable function_parameter_count - each is a part of the name
    /// "KTP - Sewa kos - Simpanin 4 Nov 2026 - hal 1.jpg": never a number, a name or a label.
    static func fileName(type: String, purpose: String, page: Int, of count: Int, date: Date, timeZone: TimeZone)
        -> String
    {
        // Characters a target or a file system can refuse in a name.
        let refused = CharacterSet(charactersIn: "/\\:*?\"<>|").union(.controlCharacters)
        let words = purpose.components(separatedBy: refused).joined(separator: " ")
            .split(separator: " ").joined(separator: " ")
        let shortPurpose = String(words.prefix(purposeLength)).trimmingCharacters(in: .whitespaces)
        var parts = [type]
        if !shortPurpose.isEmpty { parts.append(shortPurpose) }
        parts.append("Simpanin \(date.formatted(.indonesianDate(timeZone: timeZone)))")
        if count > 1 { parts.append("hal \(page)") }
        return parts.joined(separator: " - ") + ".jpg"
    }
    // swiftlint:enable function_parameter_count

    /// A file list shows about this much of a name before cutting it.
    static let purposeLength = 30

    private var root: URL { temporary.appending(path: Self.folderName, directoryHint: .isDirectory) }

    func makeFolder() throws -> URL {
        let folder = root.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try protector.protect(root, as: .complete)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        try protector.protect(folder, as: .complete)
        return folder
    }

    /// One marked page as a JPEG with no metadata. A full disk is `storageFull`, as in the vault.
    func write(_ page: CGImage, named name: String, in folder: URL) throws -> URL {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)
        else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(
            destination, page, [kCGImageDestinationLossyCompressionQuality: Self.jpegQuality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        let url = folder.appending(path: name)
        do {
            try writeFile(data as Data, url)
        } catch {
            throw VaultStore.isOutOfSpace(error) ? VaultError.storageFull : error
        }
        return url
    }

    func remove(_ folder: URL) throws {
        do {
            try FileManager.default.removeItem(at: folder)
        } catch CocoaError.fileNoSuchFile {
            // Already gone: a lock's clear can come first.
        }
    }

    /// Every shared copy, ours and the share sheet's own. At launch and on a lock, when no share can be open.
    /// Every item is tried even when one fails; the first error is thrown at the end.
    func clear() throws {
        try removeItems { $0 == Self.folderName || $0.hasPrefix(Self.shareSheetPrefix) }
    }

    /// The copies a share target had the share sheet make. Once a sheet has closed, nothing still reads them.
    func clearShareSheetCopies() throws {
        try removeItems { $0.hasPrefix(Self.shareSheetPrefix) }
    }

    private func removeItems(named matches: (String) -> Bool) throws {
        var firstError: (any Error)?
        let items = try FileManager.default.contentsOfDirectory(at: temporary, includingPropertiesForKeys: nil)
        for item in items where matches(item.lastPathComponent) {
            do { try remove(item) } catch { firstError = firstError ?? error }
        }
        if let firstError { throw firstError }
    }

    /// Clears tmp. A failure is logged, never ignored: it would leave a page on disk.
    static func clear() {
        do {
            try SharedCopies().clear()
        } catch {
            Logger.share.error("Shared copies weren't removed: \(ErrorSummary.describe(error), privacy: .public)")
        }
    }
}
