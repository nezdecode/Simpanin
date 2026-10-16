//
//  FileChanges.swift
//  Simpanin
//
//  Created by Inez Amanda on 16/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

#if DEBUG
    import Foundation

    /// DEBUG only. Which files appeared or changed in some folders, to see whether VisionKit leaves page
    /// images behind after a scan. Reports paths and sizes only, never contents.
    nonisolated struct FileChanges: Equatable, Sendable {
        /// Path relative to its folder, with the folder's name in front, and the file's size in bytes.
        struct Change: Equatable, Sendable {
            var path: String
            var size: Int
        }

        private let folders: [URL]
        private let before: [String: Date]

        /// Takes the snapshot now.
        init(folders: [URL]) {
            self.folders = folders
            before = Self.files(in: folders).mapValues(\.modified)
        }

        /// Files that are new since the snapshot, or were written to since, sorted by path.
        func changes() -> [Change] {
            Self.files(in: folders)
                .filter { path, file in before[path] != file.modified }
                .map { Change(path: $0.key, size: $0.value.size) }
                .sorted { $0.path < $1.path }
        }

        private static func files(in folders: [URL]) -> [String: (modified: Date, size: Int)] {
            let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]
            var files: [String: (modified: Date, size: Int)] = [:]
            for folder in folders {
                // tmp sits under /var, a link to /private/var, so both sides are resolved before comparing.
                let root = folder.resolvingSymlinksInPath().path
                guard let items = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys)
                else { continue }
                for case let url as URL in items {
                    guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true
                    else { continue }
                    let path = url.resolvingSymlinksInPath().path
                    let relative = path.hasPrefix(root) ? String(path.dropFirst(root.count)) : path
                    files[folder.lastPathComponent + relative] = (
                        values.contentModificationDate ?? .distantPast, values.fileSize ?? 0
                    )
                }
            }
            return files
        }
    }
#endif
