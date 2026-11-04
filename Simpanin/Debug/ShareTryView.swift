//
//  ShareTryView.swift
//  Simpanin
//
//  Created by Inez Amanda on 4/11/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

#if DEBUG
    import SwiftUI
    import UIKit
    import UniformTypeIdentifiers

    /// DEBUG only. Shares a synthetic page, to see what the share sheet and its targets leave on disk, when
    /// completion fires, and what a lock does meanwhile. Lines go to the lock's log, which outlives a lock, so
    /// Device checks' report shows them. Paths and sizes only, never contents.
    struct ShareTryView: View {
        enum Mode: String, CaseIterable, Identifiable {
            case fileComplete = "File, Complete"
            case fileUnlessOpen = "File, CompleteUnlessOpen"
            case data = "Data in memory"
            case image = "UIImage in memory"

            var id: Self { self }
            var protection: FileProtectionType? {
                switch self {
                case .fileComplete: .complete
                case .fileUnlessOpen: .completeUnlessOpen
                case .data, .image: nil
                }
            }
        }

        /// Set once the handler has run, so the watch below stops.
        private final class Outcome {
            var finished = false
        }

        static let folder = URL.temporaryDirectory.appending(path: "ShareTry", directoryHint: .isDirectory)

        let lock: LockController
        @State private var mode = Mode.fileComplete
        @State private var large = false
        @State private var excludes = true
        @State private var deleteAtCompletion = true
        @State private var shares = 0
        @State private var snapshot: FileChanges?

        private var watchedFolders: [URL] {
            var folders: [URL] = [.temporaryDirectory, .libraryDirectory, .documentsDirectory]
            if let group = AppConfiguration.appGroup,
                let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
            {
                folders.append(container)
            }
            return folders
        }

        private var shownLines: [String] { lock.attemptLog.filter { $0.hasPrefix("share") } }

        var body: some View {
            Form {
                Section {
                    Picker("Hand over as", selection: $mode) {
                        ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Toggle("Large page (6000 px, several MB)", isOn: $large)
                    Toggle("Exclude Save to Photos, Copy, Contact", isOn: $excludes)
                    Toggle("Delete the file at completion", isOn: $deleteAtCompletion)
                        .disabled(mode.protection == nil)
                    Button("Share a sample page") { share() }
                } footer: {
                    Text(
                        "A grey CONTOH card with a test NIK. For each target, note whether it got the page, the "
                            + "file name it shows, and whether the cover hid the sheet in the app switcher and "
                            + "while recording. The lines below say what was left on disk."
                    )
                }
                Section {
                    Button("List files changed since the last share") { logChanges(shares, "now", snapshot) }
                    Button("Delete the share folder", role: .destructive) { removeFolder(shares) }
                    Button("List the share sheet's own copies") { logSheetCopies(shares, "now") }
                    Button("Delete the share sheet's own copies", role: .destructive) { removeSheetCopies(shares) }
                }
                Section("Lines (also in the report)") {
                    Text(shownLines.isEmpty ? "None yet." : shownLines.joined(separator: "\n"))
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
            }
            .navigationTitle("Coba bagikan")
        }

        private func share() {
            shares += 1
            let number = shares
            let mode = mode
            let deleteAtCompletion = deleteAtCompletion && mode.protection != nil
            let before = FileChanges(folders: watchedFolders)
            snapshot = before
            let image = Self.samplePage(large: large)
            guard let data = image.jpegData(compressionQuality: 0.9) else {
                log(number, "no JPEG")
                return
            }
            guard let item = item(for: mode, image: image, data: data, share: number) else { return }
            log(number, "\(mode.rawValue), \(data.count / 1024) KB, excludes \(excludes)")

            let activity = UIActivityViewController(activityItems: [item], applicationActivities: nil)
            if excludes { activity.excludedActivityTypes = [.saveToCameraRoll, .copyToPasteboard, .assignToContact] }
            let started = Date.now
            let outcome = Outcome()
            activity.completionWithItemsHandler = { type, completed, _, error in
                outcome.finished = true
                let seconds = Int(Date.now.timeIntervalSince(started))
                var line = "\(type?.rawValue ?? "no activity"), completed \(completed), after \(seconds) s"
                if let error = error as NSError? { line += ", error \(error.domain) \(error.code)" }
                log(number, line)
                if mode.protection != nil { logClasses(number) }
                logChanges(number, "at completion", before)
                logSheetCopies(number, "at completion")
                if deleteAtCompletion { removeFolder(number) }
                Task {
                    try? await Task.sleep(for: .seconds(60))
                    logChanges(number, "60 s later", before)
                    logSheetCopies(number, "60 s later")
                }
            }
            guard present(activity) else {
                log(number, "nothing to present from")
                return
            }
            watch(activity, outcome: outcome, share: number)
        }

        private func item(for mode: Mode, image: UIImage, data: Data, share number: Int) -> Any? {
            let name = "Simpanin \(Date.now.formatted(.indonesianDate(timeZone: .current))) halaman 1.jpg"
            switch mode {
            case .fileComplete, .fileUnlessOpen:
                return write(data, named: name, protection: mode.protection, share: number)
            case .data:
                let provider = NSItemProvider(item: data as NSData, typeIdentifier: UTType.jpeg.identifier)
                provider.suggestedName = name
                return provider
            case .image:
                return image
            }
        }

        private func logClasses(_ number: Int) {
            for (path, protection) in FileChanges.protectionClasses(in: Self.folder).sorted(by: { $0.key < $1.key }) {
                log(number, "class \(path): \(protection)")
            }
        }

        /// Notes a lock while the sheet is up, and whether the sheet is still on screen then.
        private func watch(_ activity: UIActivityViewController, outcome: Outcome, share number: Int) {
            let lock = lock
            Task { [weak activity] in
                var lockSeen = false
                while !outcome.finished, let shown = activity, !Task.isCancelled {
                    if !lockSeen, lock.state != .unlocked {
                        lockSeen = true
                        log(
                            number,
                            "vault locked with the sheet up; sheet on screen: \(shown.viewIfLoaded?.window != nil)")
                    }
                    try? await Task.sleep(for: .milliseconds(500))
                }
                if !outcome.finished { log(number, "sheet gone without a completion") }
            }
        }

        private func write(_ data: Data, named name: String, protection: FileProtectionType?, share number: Int)
            -> URL?
        {
            let folder = Self.folder.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            let url = folder.appending(path: name)
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                if let protection {
                    try FileManager.default.setAttributes([.protectionKey: protection], ofItemAtPath: Self.folder.path)
                    try FileManager.default.setAttributes([.protectionKey: protection], ofItemAtPath: folder.path)
                }
                try data.write(to: url)
                if let protection {
                    try FileManager.default.setAttributes([.protectionKey: protection], ofItemAtPath: url.path)
                }
                return url
            } catch {
                let error = error as NSError
                log(number, "write failed: \(error.domain) \(error.code)")
                return nil
            }
        }

        private func removeFolder(_ number: Int) {
            do {
                if FileManager.default.fileExists(atPath: Self.folder.path) {
                    try FileManager.default.removeItem(at: Self.folder)
                }
                log(number, "share folder deleted")
            } catch {
                let error = error as NSError
                log(number, "share folder not deleted: \(error.domain) \(error.code)")
            }
        }

        private func logChanges(_ number: Int, _ moment: String, _ before: FileChanges?) {
            guard let before else {
                log(number, "\(moment): no share yet")
                return
            }
            let changes = before.changes()
            log(number, "\(moment): \(changes.isEmpty ? "no files changed" : "\(changes.count) files changed")")
            for change in changes { log(number, "  \(change.path) \(change.size) B") }
        }

        private func log(_ number: Int, _ line: String) { lock.log("share \(number): \(line)") }

        /// The share sheet copies what it's given into a dot folder in our tmp and leaves it there.
        private static func sheetCopies() -> [URL] {
            let items =
                (try? FileManager.default.contentsOfDirectory(
                    at: .temporaryDirectory, includingPropertiesForKeys: nil, options: [])) ?? []
            return items.filter { $0.lastPathComponent.hasPrefix(".com.apple.ShareSheet") }
        }

        private func logSheetCopies(_ number: Int, _ moment: String) {
            let folders = Self.sheetCopies()
            log(number, "\(moment): \(folders.count) share sheet folders")
            for folder in folders {
                for (path, protection) in FileChanges.protectionClasses(in: folder).sorted(by: { $0.key < $1.key }) {
                    log(number, "  sheet \(path): \(protection)")
                }
            }
        }

        private func removeSheetCopies(_ number: Int) {
            for folder in Self.sheetCopies() {
                do {
                    try FileManager.default.removeItem(at: folder)
                    log(number, "share sheet folder deleted")
                } catch {
                    let error = error as NSError
                    log(number, "share sheet folder not deleted: \(error.domain) \(error.code)")
                }
            }
        }

        /// The sheet goes on the topmost screen of the app's own window, never the cover's.
        private func present(_ controller: UIViewController) -> Bool {
            let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            guard let window = scene?.windows.first(where: { $0.windowLevel == .normal }),
                var top = window.rootViewController
            else { return false }
            while let next = top.presentedViewController { top = next }
            controller.popoverPresentationController?.sourceView = top.view
            top.present(controller, animated: true)
            return true
        }

        /// Synthetic: a grey card, CONTOH and a test NIK that starts with 00. The large one adds blocks of
        /// colour so the JPEG is several MB and a transfer takes long enough to lock the phone during it.
        private static func samplePage(large: Bool) -> UIImage {
            let size = large ? CGSize(width: 6000, height: 3780) : CGSize(width: 1712, height: 1080)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            return UIGraphicsImageRenderer(size: size, format: format).image { context in
                UIColor.systemGray4.setFill()
                context.fill(CGRect(origin: .zero, size: size))
                if large {
                    var generator = SystemRandomNumberGenerator()
                    for _ in 0..<40_000 {
                        UIColor(hue: .random(in: 0...1, using: &generator), saturation: 0.5, brightness: 0.8, alpha: 1)
                            .setFill()
                        let origin = CGPoint(
                            x: .random(in: 0..<size.width, using: &generator),
                            y: .random(in: 0..<size.height, using: &generator))
                        context.fill(CGRect(origin: origin, size: CGSize(width: 24, height: 24)))
                    }
                }
                let font = UIFont.boldSystemFont(ofSize: size.height / 9)
                for (index, line) in ["CONTOH", "NIK 0012345678901234"].enumerated() {
                    NSAttributedString(string: line, attributes: [.font: font, .foregroundColor: UIColor.black])
                        .draw(
                            at: CGPoint(x: size.width / 14, y: size.height / 5 + CGFloat(index) * font.lineHeight * 1.4)
                        )
                }
            }
        }
    }
#endif
