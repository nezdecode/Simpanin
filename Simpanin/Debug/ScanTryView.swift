//
//  ScanTryView.swift
//  Simpanin
//
//  Created by Inez Amanda on 16/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

#if DEBUG
    import Parsers
    import SwiftUI
    import VaultCore

    /// DEBUG only. Scans a document and shows what Vision and the parsers read, so scanning can be tried
    /// on the phone before the review screen exists. Saves nothing, and drops the scan when the vault
    /// locks, like the real flow.
    struct ScanTryView: View {
        let lock: LockController
        @State private var scan = ScanModel()
        @State private var cameraShown = false
        @State private var snapshot: FileChanges?
        @State private var leftovers: [FileChanges.Change]?

        /// Where VisionKit could leave page images: tmp, and Library with its Caches.
        private static var watchedFolders: [URL] { [.temporaryDirectory, .libraryDirectory] }

        private static let shownFields = [FieldKey.nik, FieldKey.simNumber, FieldKey.name, FieldKey.birthDate]

        private var method: Binding<RecognitionMethod> {
            Binding(get: { scan.method }, set: { method in Task { await scan.read(using: method) } })
        }

        var body: some View {
            Form {
                Section {
                    Button("Scan") {
                        snapshot = FileChanges(folders: Self.watchedFolders)
                        leftovers = nil
                        cameraShown = true
                    }
                    .disabled(!DocumentCamera.isSupported || scan.state == .reading)
                    Picker("Vision request", selection: method) {
                        Text("RecognizeText").tag(RecognitionMethod.text)
                        Text("RecognizeDocuments").tag(RecognitionMethod.document)
                    }
                    .pickerStyle(.segmented)
                    .disabled(scan.pages.isEmpty || scan.state == .reading)
                } footer: {
                    Text(
                        DocumentCamera.isSupported
                            ? "Switching the request reads the same pages again."
                            : "The document camera only runs on an iPhone.")
                }
                Section("Result") { resultRows }
                if !scan.lines.isEmpty {
                    Section("Recognised text, \(scan.lines.count) lines") {
                        ForEach(Array(scan.lines.enumerated()), id: \.offset) { _, line in
                            Text(verbatim: line).font(.caption.monospaced())
                        }
                    }
                }
                leftoversSection
                if scan.state != .empty {
                    Button("Drop the scan", role: .destructive) {
                        scan.discard()
                        leftovers = nil
                    }
                }
            }
            .navigationTitle("Coba pindai")
            .fullScreenCover(isPresented: $cameraShown) {
                DocumentCamera(
                    onFinish: { pages in
                        cameraShown = false
                        Task {
                            await scan.scanned(pages)
                            leftovers = snapshot?.changes()
                        }
                    },
                    onCancel: { cameraShown = false }
                )
                .ignoresSafeArea()
            }
            .onChange(of: lock.state) { _, state in
                if state != .unlocked { scan.discard() }
            }
        }

        /// Swift 6.4 crashed compiling `if let leftovers {` inside the Form, so this has its own property.
        @ViewBuilder private var leftoversSection: some View {
            if let changes = leftovers {
                Section {
                    if changes.isEmpty {
                        Text("No new or changed files in tmp or Library.")
                    }
                    ForEach(changes, id: \.path) { file in
                        Text(verbatim: "\(file.path) (\(file.size) bytes)").font(.caption.monospaced())
                    }
                    Button("Check again") { leftovers = snapshot?.changes() }
                } header: {
                    Text("Files since the scan")
                } footer: {
                    Text("An image file here would be an unencrypted page left by VisionKit.")
                }
            }
        }

        @ViewBuilder private var resultRows: some View {
            switch scan.state {
            case .empty: Text("No scan yet.")
            case .reading: ProgressView()
            case .failed: Text("Recognition failed.")
            case .read:
                if let result = scan.result {
                    row(Text(DocumentStyle.name(result.type)), label: "type", marked: result.typeNeedsCheck)
                    ForEach(Self.shownFields, id: \.self) { key in
                        if let value = result.fields.values[key] {
                            row(Text(verbatim: value), label: key, marked: result.needsCheck.contains(key))
                        } else if result.needsCheck.contains(key) {
                            row(Text(verbatim: "–"), label: key, marked: true)
                        }
                    }
                    if result.expiry != nil || result.expiryNeedsCheck {
                        row(
                            Text(verbatim: result.expiry?.displayText ?? "–"), label: "expiry",
                            marked: result.expiryNeedsCheck)
                    }
                } else {
                    Text("Not a KTP or SIM: the review screen will offer Lainnya.")
                }
            }
        }

        private func row(_ value: Text, label: String, marked: Bool) -> some View {
            LabeledContent {
                VStack(alignment: .trailing) {
                    value
                    if marked { Text("Periksa lagi").font(.caption).foregroundStyle(Color(.warning)) }
                }
            } label: {
                Text(verbatim: label)
            }
        }
    }
#endif
