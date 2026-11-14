//
//  AppInfoTests.swift
//  SimpaninTests
//
//  Created by Inez Amanda on 15/11/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import Testing

@Suite("App Info.plist")
struct AppInfoTests {
    private let info = Bundle.main.infoDictionary ?? [:]

    /// The app is planned and tested on iPhone only; on an iPad it runs as an iPhone app.
    @Test func theAppIsForIPhoneOnly() {
        #expect(info["UIDeviceFamily"] as? [Int] == [1])
    }

    /// Each window would get its own lock over the one vault, so a second window could
    /// keep showing a document after Kunci in the first.
    @Test func theAppHasOneWindow() throws {
        let manifest = try #require(info["UIApplicationSceneManifest"] as? [String: Any])
        #expect(manifest["UIApplicationSupportsMultipleScenes"] as? Bool == false)
    }

    /// Only the system's encryption is used (CryptoKit, the Keychain, Data Protection), which is exempt.
    @Test func theExportAnswerIsTheExemptOne() {
        #expect(info["ITSAppUsesNonExemptEncryption"] as? Bool == false)
    }
}
