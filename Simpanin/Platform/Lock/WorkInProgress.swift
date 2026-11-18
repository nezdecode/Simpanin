//
//  WorkInProgress.swift
//  Simpanin
//
//  Created by Inez Amanda on 18/11/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

/// What a lock removes from the screen, so the next unlock can say what was dropped, once.
struct WorkInProgress {
    var scanInProgress: ScanSource?
    /// A lock dropped a scan; told once, after the next unlock.
    private var scanDroppedByLock: ScanSource?
    var shareSheetUp = false
    /// A lock came while the share sheet was up; told once, after the next unlock.
    private var shareStoppedByLock = false
    /// Edit dokumen holds changes not saved yet.
    var editUnsaved = false
    /// A lock dropped them; told once, after the next unlock.
    private var editDroppedByLock = false

    /// Locking removes every screen, a scan in progress with it; say so after unlocking.
    mutating func lockLanded() {
        if let scanInProgress { scanDroppedByLock = scanInProgress }
        scanInProgress = nil
        if shareSheetUp { shareStoppedByLock = true }
        shareSheetUp = false
        if editUnsaved { editDroppedByLock = true }
        editUnsaved = false
    }

    /// The notices for what the locks since the last unlock dropped, handed over once.
    mutating func takeNotices() -> Set<VaultNotice> {
        var notices: Set<VaultNotice> = []
        switch scanDroppedByLock {
        case .camera: notices.insert(.scanDropped)
        case .photos: notices.insert(.photosDropped)
        case nil: break
        }
        if shareStoppedByLock { notices.insert(.shareStopped) }
        if editDroppedByLock { notices.insert(.editDropped) }
        scanDroppedByLock = nil
        shareStoppedByLock = false
        editDroppedByLock = false
        return notices
    }
}
