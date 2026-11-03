//
//  ScanFlowView.swift
//  Simpanin
//
//  Created by Inez Amanda on 16/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import PhotosUI
import SwiftUI
import VaultCore

/// From "+" to a saved document: the camera or photos picked in Photos, Vision reading the pages, then
/// "Periksa data". The scan lives only in memory; Batal, saving and the lock all drop it, and VisionKit's
/// copies are removed.
struct ScanFlowView: View {
    let source: ScanSource
    /// For the lock, which drops a scan in progress and says so after unlocking.
    let onScanStarted: (ScanSource) -> Void
    let onScanEnded: () -> Void
    /// The pages were read and the review shows them.
    let onRead: () -> Void
    /// Called when the flow ends, saved or not.
    let onDone: () -> Void
    @State private var review: ReviewModel
    @State private var scan: ScanModel
    @State private var photos: PhotoImportModel
    @State private var cameraShown = false
    /// Reads, photo loads and saves run in `.task(id:)`, so SwiftUI cancels them when the flow goes away.
    @State private var reads = 0
    @State private var photoLoads = 0
    @State private var saves = 0
    @State private var newPages: [CGImage]?
    /// The picked files behind `newPages`, which Simpan decodes again at the stored size.
    @State private var newPhotos: [Data]?
    @State private var rescanConfirmShown = false
    @State private var pageFailedShown = false
    @State private var started = false

    init(
        source: ScanSource, store: any DocumentStoring, onScanStarted: @escaping (ScanSource) -> Void,
        onScanEnded: @escaping () -> Void, onRead: @escaping () -> Void = {}, onDone: @escaping () -> Void
    ) {
        self.source = source
        self.onScanStarted = onScanStarted
        self.onScanEnded = onScanEnded
        self.onRead = onRead
        self.onDone = onDone
        _review = State(initialValue: ReviewModel(store: store))
        _scan = State(initialValue: ScanModel(recognizer: Self.recognizer))
        // Photos count as started only on Tambah: ticking a photo is no decision yet.
        let photos = PhotoImportModel(loader: Self.photoLoader, onStarted: { onScanStarted(.photos) })
        #if DEBUG
            photos.selection = UITestSetup.syntheticPhotoSelection
        #endif
        _photos = State(initialValue: photos)
        // Shown from the first frame, so "+" never shows an empty review first.
        _cameraShown = State(initialValue: source == .camera && !Self.scansSynthetically)
    }

    private static var scansSynthetically: Bool {
        #if DEBUG
            UITestSetup.scansSynthetically
        #else
            false
        #endif
    }

    private static var photoLoader: any PhotoLoading {
        #if DEBUG
            if let mode = UITestSetup.picksPhotos { return UITestSetup.SyntheticPhotos(mode: mode) }
        #endif
        return PhotosPickerLoader()
    }

    private static var recognizer: @Sendable (RecognitionMethod) -> any TextRecognizer {
        #if DEBUG
            if UITestSetup.scansSynthetically || UITestSetup.picksPhotos != nil {
                return { _ in UITestSetup.SyntheticRecognizer() }
            }
        #endif
        return { VisionTextRecognizer(method: $0) }
    }

    var body: some View {
        // The camera is the flow's own content, not a screen presented over the review, so "+" shows it
        // at once and no second presentation can fail while the first is still animating in.
        Group {
            if source == .photos, photos.screen == .picker {
                PhotoPickerView(selection: $photos.selection, onCancel: photos.cancelPicker) {
                    photos.add()
                    photoLoads += 1
                }
            } else if source == .photos, photos.screen == .loading {
                PhotoLoadingView(
                    number: photos.loadingNumber, count: photos.loadingCount, onCancel: photos.cancel)
            } else if cameraShown {
                DocumentCamera(
                    onFinish: { pages in
                        cameraShown = false
                        newPages = pages
                        reads += 1
                    },
                    onCancel: {
                        cameraShown = false
                        // Cancelling the first scan ends the flow; cancelling a rescan keeps the scan before it.
                        if review.pages.isEmpty { end() }
                    },
                    onPageFailed: {
                        cameraShown = false
                        pageFailedShown = true
                    }
                )
                .ignoresSafeArea()
                // VisionKit may still write its copies after handing the pages back, so clear once it's gone.
                .onDisappear(perform: DocumentCameraCache.clear)
            } else {
                ReviewView(
                    review: review, source: source, reading: review.pages.isEmpty || scan.state == .reading,
                    onCancel: end, onRescan: rescan, onSave: save)
            }
        }
        .task(id: photoLoads) {
            guard let picked = await photos.loadAdded() else { return }
            newPages = picked.pages
            newPhotos = picked.photos
            reads += 1
        }
        .task(id: reads) {
            guard let pages = newPages else { return }
            let saved = newPhotos.map(SavedPages.photos) ?? .shownPages
            newPages = nil
            newPhotos = nil
            // Made while the text is read, so they're ready when it is.
            async let thumbnails = PageThumbnail.made(of: pages)
            await scan.scanned(pages)
            let made = await thumbnails
            guard !Task.isCancelled else { return }
            // Text Vision couldn't read is still a scan: the user picks the type and can save the pages.
            let read = scan.state == .read
            review.load(
                read ? scan.result : nil, pages: pages, thumbnails: made, reading: read ? scan.reading : nil,
                saving: saved)
            scan.discard()
            onRead()
        }
        // Not cancelled once the vault is writing: the save checks for the lock only while it prepares pages.
        .task(id: saves) {
            guard saves > 0 else { return }
            // The scan ends the moment the vault has it, so a lock right after doesn't call it dropped.
            if await review.save(onSaved: onScanEnded) { end() }
        }
        .onAppear(perform: start)
        .onChange(of: photos.screen) { _, screen in
            if screen == .ended { end() }
        }
        .confirmationDialog(
            Text(ReviewText.rescanConfirm(source)), isPresented: $rescanConfirmShown, titleVisibility: .visible
        ) {
            Button(action: scanAgain) { Text(ReviewText.rescan(source)) }
        }
        .alert(
            Text("photos.failed"),
            isPresented: Binding {
                photos.state == .failed
            } set: {
                if !$0 { photos.failureSeen() }
            }
        ) {
            Button(action: photos.failureSeen) { Text(ScreenText.okay) }
        } message: {
            Text("photos.failed.message")
        }
        .alert(Text("review.pageFailed"), isPresented: $pageFailedShown) {
            Button {
                if review.pages.isEmpty { end() }
            } label: {
                Text(ScreenText.okay)
            }
        }
        .alert(
            review.saveError.map { Text(RecoveryContent($0).message) } ?? Text(verbatim: ""),
            isPresented: Binding(isPresent: $review.saveError)
        ) {
            Button {
                review.saveError = nil
            } label: {
                Text(ScreenText.okay)
            }
        } message: {
            if review.saveError == .storageFullOnSave { Text("saveFull.hint") }
        }
    }

    private func start() {
        // onAppear can run again when the flow reappears; the scan starts once.
        guard !started else { return }
        started = true
        guard source == .camera else { return }
        onScanStarted(.camera)
        // The camera is already showing; UI tests read their synthetic page instead.
        if Self.scansSynthetically { openCamera() }
    }

    private func openCamera() {
        #if DEBUG
            // The simulator has no camera; UI tests read a synthetic page instead.
            if UITestSetup.scansSynthetically {
                newPages = UITestSetup.syntheticPages
                reads += 1
                return
            }
        #endif
        cameraShown = true
    }

    /// A rescan may be a different card, so it replaces every field; changes are confirmed first.
    private func rescan() {
        if review.hasUserChanges {
            rescanConfirmShown = true
        } else {
            scanAgain()
        }
    }

    private func scanAgain() {
        if source == .photos { photos.pickAgain() } else { openCamera() }
    }

    private func save() {
        // A new id cancels the task before it, so a save already running is never replaced.
        guard !review.saving else { return }
        saves += 1
    }

    private func end() {
        DocumentCameraCache.clear()
        onScanEnded()
        onDone()
    }
}
