//
//  PasscodeSteps.swift
//  Simpanin
//
//  Created by Inez Amanda on 15/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

/// The three steps to turn on a passcode. The button can only open Simpanin's own page in
/// Settings, so the steps start from the main Settings screen.
struct PasscodeSteps: View {
    private let method = UnlockMethod.current()

    private var stepTwo: LocalizedStringResource {
        switch method {
        case .faceID, .faceIDTurnedOff: "onboarding.step2.faceID"
        case .touchID: "onboarding.step2.touchID"
        case .opticID, .passcode: "onboarding.step2.passcode"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            step(1, "onboarding.step1")
            step(2, stepTwo)
            step(3, "onboarding.step3")
        }
        .padding(.top, 8)
    }

    private func step(_ number: Int, _ text: LocalizedStringResource) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(number, format: .number)
                .font(.subheadline.bold())
                .frame(width: 28, height: 28)
                .background(Color(.secondarySystemBackground), in: .circle)
            Text(text)
        }
    }
}
