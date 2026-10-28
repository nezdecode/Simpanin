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
    import UniformTypeIdentifiers
    import VaultCore

    /// DEBUG only. Scans a document and shows what Vision and the parsers read, so scanning can be tried
    /// on the phone before the review screen exists. Saves nothing. Locking the vault removes this screen,
    /// which cancels a read and drops the scan; RootView removes VisionKit's page images.
    struct ScanTryView: View {
        @State private var scan = ScanModel()
        @State private var cameraShown = false
        @State private var snapshot: FileChanges?
        @State private var leftovers: [FileChanges.Change]?
        /// What VisionKit's folder held while the camera was open, with each item's protection class.
        @State private var whileOpen: [String: String] = [:]
        /// Reads run in `.task(id: reads)`, so SwiftUI cancels one when the screen goes away.
        @State private var reads = 0
        @State private var newPages: [CGImage]?
        @State private var requestedMethod = RecognitionMethod.text
        /// The class letter spike's reading of the source page; nil until a SIM has been read.
        @State private var classLetter: Result<ClassLetterSpike.Reading, any Error>?

        /// Where VisionKit could leave page images: tmp, and Library with its Caches.
        private static var watchedFolders: [URL] { [.temporaryDirectory, .libraryDirectory] }

        private static let shownFields = [FieldKey.nik, FieldKey.simNumber, FieldKey.name, FieldKey.birthDate]

        private var method: Binding<RecognitionMethod> {
            Binding(
                get: { scan.method },
                set: { method in
                    requestedMethod = method
                    reads += 1
                })
        }

        var body: some View {
            Form {
                Section {
                    Button("Scan") {
                        snapshot = FileChanges(folders: Self.watchedFolders)
                        leftovers = nil
                        whileOpen = [:]
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
                classLetterSection
                if let reading = scan.reading, reading.pages.count > 1 {
                    Section("Pages") { pageRows(reading) }
                }
                if !scan.lines.isEmpty {
                    Section("Recognised text, \(scan.lines.count) lines") {
                        ForEach(Array(scan.lines.enumerated()), id: \.offset) { _, line in
                            Text(verbatim: line).font(.caption.monospaced())
                        }
                        // Local only, so it doesn't reach the Mac through Universal Clipboard.
                        Button("Copy masked text") {
                            UIPasteboard.general.setItems(
                                [[UTType.plainText.identifier: MaskedText.mask(scan.lines)]],
                                options: [.localOnly: true, .expirationDate: Date.now.addingTimeInterval(60)])
                        }
                    }
                }
                leftoversSection
                protectionSection
                if scan.state != .empty {
                    Button("Drop the scan", role: .destructive) {
                        scan.discard()
                        DocumentCameraCache.clear()
                        leftovers = nil
                        classLetter = nil
                    }
                }
            }
            .navigationTitle("Coba pindai")
            // VisionKit may still write its copies after it hands the pages back, so clear again once it's gone.
            .fullScreenCover(isPresented: $cameraShown, onDismiss: DocumentCameraCache.clear) {
                DocumentCamera(
                    onFinish: { pages in
                        cameraShown = false
                        newPages = pages
                        reads += 1
                    },
                    onCancel: { cameraShown = false },
                    onPageFailed: { cameraShown = false }
                )
                .ignoresSafeArea()
            }
            // VisionKit removes nothing until the camera closes, and Simpanin clears the folder before the
            // pages arrive, so the folder is looked at while the camera is still open.
            .task(id: cameraShown) {
                let folder = URL.cachesDirectory.appending(path: DocumentCameraCache.folderName)
                while cameraShown, !Task.isCancelled {
                    whileOpen.merge(FileChanges.protectionClasses(in: folder)) { _, new in new }
                    try? await Task.sleep(for: .milliseconds(500))
                }
            }
            .task(id: reads) {
                guard reads > 0 else { return }
                classLetter = nil
                if let pages = newPages {
                    newPages = nil
                    await scan.scanned(pages)
                    leftovers = snapshot?.changes()
                } else {
                    await scan.read(using: requestedMethod)
                }
                guard scan.result?.type.isSIM == true, !Task.isCancelled else { return }
                let page = scan.reading?.source ?? 0
                guard scan.pages.indices.contains(page) else { return }
                let image = scan.pages[page]
                let reading: Result<ClassLetterSpike.Reading, any Error>
                do {
                    reading = .success(try await ClassLetterSpike.read(image))
                } catch {
                    reading = .failure(error)
                }
                // Dropping the scan doesn't cancel this task, so a late reading must not bring its page back.
                guard !Task.isCancelled, scan.pages.indices.contains(page), scan.pages[page] === image else { return }
                classLetter = reading
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
                    Text(
                        "An image file here would be an unencrypted page left by VisionKit. Files under "
                            + "com.apple.metal are the GPU's shader cache, made the first time Vision runs: "
                            + "no page data."
                    )
                }
            }
        }

        @ViewBuilder private var classLetterSection: some View {
            switch classLetter {
            case nil: EmptyView()
            case .failure: Section("Class letter (spike)") { Text("Recognition failed.") }
            case .success(.noNumber):
                Section("Class letter (spike)") { Text("No piece of text was a SIM number on its own.") }
            case .success(.nothingAbove): Section("Class letter (spike)") { Text("Nothing above the number.") }
            case .success(.read(let crop, let outcomes)):
                Section {
                    Image(decorative: crop, scale: 1).resizable().scaledToFit().frame(maxHeight: 120)
                    ForEach(ClassLetterSpike.variants.indices, id: \.self) { index in
                        LabeledContent {
                            Text(verbatim: Self.text(outcomes[index]))
                        } label: {
                            Text(verbatim: ClassLetterSpike.variants[index].name)
                        }
                    }
                } header: {
                    Text("Class letter (spike)")
                } footer: {
                    Text("The area above the number, read seven ways. Only the class each way matched is shown.")
                }
            }
        }

        private static func text(_ outcome: ClassLetterSpike.Outcome) -> String {
            switch outcome {
            case .matched(let type): type.rawValue
            case .noClass: "–"
            case .failed: "failed"
            }
        }

        @ViewBuilder private var protectionSection: some View {
            if !whileOpen.isEmpty {
                Section {
                    ForEach(whileOpen.keys.sorted(), id: \.self) { path in
                        Text(verbatim: "\(path): \(whileOpen[path] ?? "")").font(.caption.monospaced())
                    }
                } header: {
                    Text("VisionKit's folder while the camera was open")
                } footer: {
                    Text("Every line should say Complete: the folder, Scans and each page file.")
                }
            }
        }

        /// What each page was read as and how it relates to the source page, by code only: a page can be
        /// another person's card, so none of its values are shown.
        private func pageRows(_ reading: ScanReading) -> some View {
            ForEach(reading.pages.indices, id: \.self) { index in
                if let page = reading.pages[index] {
                    let reasons = page.reasons.values.reduce(page.typeReasons.union(page.expiryReasons)) {
                        $0.union($1)
                    }
                    row(
                        Text(verbatim: "\(page.type.rawValue), \(page.relation)"), label: "page \(index + 1)",
                        reasons: reasons)
                } else {
                    row(Text(verbatim: "not a front"), label: "page \(index + 1)", reasons: [])
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
                    row(Text(DocumentStyle.name(result.type)), label: "type", reasons: result.typeReasons)
                    ForEach(Self.shownFields, id: \.self) { key in
                        if let value = result.fields.values[key] {
                            row(Text(verbatim: value), label: key, reasons: result.reasons[key] ?? [])
                        } else if let reasons = result.reasons[key] {
                            row(Text(verbatim: "–"), label: key, reasons: reasons)
                        }
                    }
                    if result.expiry != nil || result.expiryNeedsCheck {
                        row(
                            Text(verbatim: result.expiry?.displayText ?? "–"), label: "expiry",
                            reasons: result.expiryReasons)
                    }
                    row(
                        Text(verbatim: result.birthDateConfirmed ? "yes" : "no"), label: "birth date confirmed",
                        reasons: [])
                } else {
                    Text("Not a KTP or SIM: the review screen will offer Lainnya.")
                }
            }
        }

        /// Every reason, first the one Periksa data shows, by its code, so a failed scan can be shared as text.
        private func row(_ value: Text, label: String, reasons: Set<CheckReason>) -> some View {
            LabeledContent {
                VStack(alignment: .trailing) {
                    value
                    if !reasons.isEmpty {
                        Text(verbatim: "Periksa lagi: " + reasons.sorted().map(\.rawValue).joined(separator: ", "))
                            .font(.caption).foregroundStyle(Color(.onWarning))
                    }
                }
            } label: {
                Text(verbatim: label)
            }
        }
    }
#endif
