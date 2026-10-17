//
//  TypePickerViewTests.swift
//  SimpaninTests
//
//  Created by Inez Amanda on 16/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import Testing
import VaultCore

@testable import Simpanin

@Suite("Type picker")
struct TypePickerViewTests {
    /// Each class shows what it may drive, never its key: the key has to be looked up whole.
    @Test func everySIMClassHasItsDescription() {
        #expect(String(localized: TypePickerView.description(of: .simA)) == "Mobil sampai 3.500 kg")
        for type in DocumentType.simClasses {
            #expect(!String(localized: TypePickerView.description(of: type)).hasPrefix("simClass."), "\(type.rawValue)")
        }
    }

    /// Umum comes from the type, not from a position in the list, so a new class lands in the right section.
    @Test func simClassesSplitIntoPersonalAndUmum() {
        #expect(TypePickerView.publicSIMClasses == [.simAUmum, .simB1Umum, .simB2Umum])
        #expect(TypePickerView.personalSIMClasses == [.simA, .simB1, .simB2, .simC, .simC1, .simC2, .simD, .simD1])
    }
}
