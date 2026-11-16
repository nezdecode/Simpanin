//
//  AppSetupTests.swift
//  SimpaninTests
//
//  Created by Inez Amanda on 16/11/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Testing

@testable import Simpanin

@MainActor
@Suite("App setup")
struct AppSetupTests {
    struct SetupFailure: Error {}

    /// Fails its first `failures` calls, then makes a throwaway vault, and counts every call.
    final class Launcher {
        var failures: Int
        private(set) var calls = 0

        init(failures: Int = 0) { self.failures = failures }

        func launch() throws -> AppVault {
            calls += 1
            if calls <= failures { throw SetupFailure() }
            return .preview()
        }
    }

    @Test func aSetupThatWorkedIsNeverRunAgain() {
        let launcher = Launcher()
        let setup = AppSetup(launch: { try launcher.launch() }, cleanUp: {})
        let vault = setup.vault
        #expect(vault != nil)
        setup.sceneDidBecomeInactive()
        setup.sceneDidBecomeActive()
        setup.retry()
        #expect(launcher.calls == 1)
        #expect(setup.vault === vault)
    }

    @Test func aFailedSetupRunsAgainWhenTheSceneBecomesActive() {
        let launcher = Launcher(failures: 1)
        let setup = AppSetup(launch: { try launcher.launch() }, cleanUp: {})
        #expect(setup.vault == nil)
        setup.sceneDidBecomeActive()
        #expect(setup.vault != nil)
        #expect(launcher.calls == 2)
    }

    /// The scene is shown while inactive before it's active, so a failed setup tries again then and
    /// the failure screen doesn't flash up first.
    @Test func aFailedSetupRunsAgainWhenTheSceneBecomesInactive() {
        let launcher = Launcher(failures: 1)
        let setup = AppSetup(launch: { try launcher.launch() }, cleanUp: {})
        setup.sceneDidBecomeInactive()
        #expect(setup.vault != nil)
        #expect(launcher.calls == 2)
    }

    @Test func aFailedSetupRunsAgainOnRetry() {
        let launcher = Launcher(failures: 1)
        let setup = AppSetup(launch: { try launcher.launch() }, cleanUp: {})
        setup.retry()
        #expect(setup.vault != nil)
        #expect(launcher.calls == 2)
    }

    @Test func aSetupThatFailsAgainStaysFailed() {
        let launcher = Launcher(failures: 3)
        let setup = AppSetup(launch: { try launcher.launch() }, cleanUp: {})
        setup.sceneDidBecomeActive()
        setup.retry()
        #expect(setup.vault == nil)
        #expect(launcher.calls == 3)
        setup.retry()
        #expect(setup.vault != nil)
    }

    /// Only an active app is sure to run on an unlocked phone, so the leftovers are removed then. Only once:
    /// a later activation can come back to a scan in progress, whose pages are in the camera's folder.
    @Test(arguments: [0, 5]) func theCleanupsRunOnTheFirstActivationOnly(failures: Int) {
        var cleanups = 0
        let launcher = Launcher(failures: failures)
        let setup = AppSetup(launch: { try launcher.launch() }, cleanUp: { cleanups += 1 })
        #expect(cleanups == 0)
        setup.retry()
        setup.sceneDidBecomeInactive()
        #expect(cleanups == 0)
        setup.sceneDidBecomeActive()
        #expect(cleanups == 1)
        setup.sceneDidBecomeInactive()
        setup.sceneDidBecomeActive()
        #expect(cleanups == 1)
    }
}
