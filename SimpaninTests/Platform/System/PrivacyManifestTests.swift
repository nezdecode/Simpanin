//
//  PrivacyManifestTests.swift
//  SimpaninTests
//
//  Created by Inez Amanda on 7/11/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import Testing

@Suite("Privacy manifest")
struct PrivacyManifestTests {
    private func manifest() throws -> [String: Any] {
        let url = try #require(Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"))
        let data = try Data(contentsOf: url)
        return try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }

    /// The App Store label says "Data Not Collected", so the manifest must say the same.
    @Test func noTrackingAndNoCollectedData() throws {
        let manifest = try manifest()
        #expect(manifest["NSPrivacyTracking"] as? Bool == false)
        #expect((manifest["NSPrivacyTrackingDomains"] as? [String])?.isEmpty == true)
        #expect((manifest["NSPrivacyCollectedDataTypes"] as? [Any])?.isEmpty == true)
    }

    /// A new use of a required-reason API needs its category here, or App Store review refuses the build.
    @Test func declaresTheSettingsAndFileDateReasons() throws {
        let types = try #require(try manifest()["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        var reasons: [String: [String]] = [:]
        for type in types {
            let category = try #require(type["NSPrivacyAccessedAPIType"] as? String)
            reasons[category] = try #require(type["NSPrivacyAccessedAPITypeReasons"] as? [String])
        }
        #expect(
            reasons == [
                "NSPrivacyAccessedAPICategoryUserDefaults": ["CA92.1"],
                "NSPrivacyAccessedAPICategoryFileTimestamp": ["C617.1"],
            ])
    }
}
