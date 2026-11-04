//
//  ActivitySharePresenter.swift
//  Simpanin
//
//  Created by Inez Amanda on 4/11/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import UIKit

/// The system share sheet, shown from the app's window over the share screen.
final class ActivitySharePresenter: SharePresenting {
    /// Photos would keep a copy outside the app, the clipboard can reach other devices, and a contact photo
    /// is never what a copy is for.
    static let excludedActivityTypes: [UIActivity.ActivityType] = [
        .saveToCameraRoll, .copyToPasteboard, .assignToContact,
    ]

    static func controller(for files: [URL]) -> UIActivityViewController {
        let items = files.map { SharedPageSource(file: $0, pageCount: files.count) }
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.excludedActivityTypes = excludedActivityTypes
        return controller
    }

    func present(_ files: [URL], onClose: @escaping @MainActor (Bool) -> Void) -> Bool {
        guard let top = Self.topController() else { return false }
        let controller = Self.controller(for: files)
        // Once, when the sheet goes: after a target took the files, or with nothing chosen.
        controller.completionWithItemsHandler = { _, completed, _, _ in
            MainActor.assumeIsolated { onClose(completed) }
        }
        controller.popoverPresentationController?.sourceView = top.view
        top.present(controller, animated: true)
        return true
    }

    /// What the app's own window shows on top; the cover's window is above it and never presents.
    private static func topController() -> UIViewController? {
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
        var top =
            windows.first { $0.windowLevel == .normal && $0.isKeyWindow }?.rootViewController
            ?? windows.first { $0.windowLevel == .normal }?.rootViewController
        while let presented = top?.presentedViewController, !presented.isBeingDismissed { top = presented }
        return top
    }
}
