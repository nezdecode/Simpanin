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

import SwiftUI
import VaultCore

/// From "+" to a saved document: the camera, Vision reading the pages, then "Periksa data". The scan
/// lives only in memory; Batal, saving and the lock all drop it, and VisionKit's copies are removed.
struct ScanFlowView: View {
    let lock: LockController
    /// Called when the flow ends, saved or not.
    let onDone: () -> Void
    @State private var review: ReviewModel
    @State private var scan: ScanModel
    @State private var cameraShown = false
    /// Reads run in `.task(id: reads)`, so SwiftUI cancels one when the flow goes away.
    @State private var reads = 0
    @State private var newPages: [CGImage]?
    @State private var rescanConfirmShown = false
    @State private var pageFailedShown = false

    init(store: any DocumentStoring, lock: LockController, onDone: @escaping () -> Void) {
        self.lock = lock
        self.onDone = onDone
        _review = State(initialValue: ReviewModel(store: store))
        _scan = State(initialValue: ScanModel(recognizer: Self.recognizer))
        // Shown from the first frame, so "+" never shows an empty review first.
        _cameraShown = State(initialValue: !Self.scansSynthetically)
    }

    private static var scansSynthetically: Bool {
        #if DEBUG
            UITestSetup.scansSynthetically
        #else
            false
        #endif
    }

    private static var recognizer: @Sendable (RecognitionMethod) -> any TextRecognizer {
        #if DEBUG
            if UITestSetup.scansSynthetically { return { _ in UITestSetup.SyntheticRecognizer() } }
        #endif
        return { VisionTextRecognizer(method: $0) }
    }

    var body: some View {
        // The camera is the flow's own content, not a screen presented over the review, so "+" shows it
        // at once and no second presentation can fail while the first is still animating in.
        Group {
            if cameraShown {
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
                    review: review, reading: review.pages.isEmpty || scan.state == .reading, onCancel: end,
                    onRescan: rescan, onSave: save)
            }
        }
        .task(id: reads) {
            guard let pages = newPages else { return }
            newPages = nil
            await scan.scanned(pages)
            guard !Task.isCancelled else { return }
            // Text Vision couldn't read is still a scan: the user picks the type and can save the pages.
            review.load(scan.state == .read ? scan.result : nil, pages: pages)
            scan.discard()
            #if DEBUG
                if UITestSetup.capturesAfterScan { lock.screenCaptured = true }
            #endif
        }
        .onAppear(perform: start)
        .confirmationDialog(
            Text("review.rescanConfirm"), isPresented: $rescanConfirmShown, titleVisibility: .visible
        ) {
            Button(action: openCamera) { Text("review.rescan") }
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
        lock.scanStarted()
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
            openCamera()
        }
    }

    private func save() {
        Task {
            // The scan ends the moment the vault has it, so a lock right after doesn't call it dropped.
            if await review.save(onSaved: lock.scanEnded) { end() }
        }
    }

    private func end() {
        DocumentCameraCache.clear()
        lock.scanEnded()
        onDone()
    }
}
