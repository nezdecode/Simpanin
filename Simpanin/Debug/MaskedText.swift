//
//  MaskedText.swift
//  Simpanin
//
//  Created by Inez Amanda on 16/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

#if DEBUG
    /// DEBUG only. Recognised text with every value made unreadable, so the shape of a real scan can be
    /// shared without its data: digits become 9, letters A or a. Only the words of KTP and SIM labels
    /// stay readable, as recognition read them, so a misread label ("Tgi") still shows.
    nonisolated enum MaskedText {
        static func mask(_ lines: [String]) -> String {
            lines.map(mask(line:)).joined(separator: "\n")
        }

        /// The words of every KTP and SIM label, compared as `labelForm` reads them.
        private static let labelWords: Set<String> = Set(
            [
                "PROVINSI", "KOTA", "KABUPATEN", "NIK", "Nama", "Tempat", "Tgl", "Lahir", "Jenis", "Kelamin", "Gol",
                "Darah", "Alamat", "RT", "RW", "Kel", "Desa", "Kecamatan", "Agama", "Status", "Perkawinan",
                "Pekerjaan", "Kewarganegaraan", "Berlaku", "Hingga", "INDONESIA", "SURAT", "IZIN", "MENGEMUDI",
                "DRIVING", "LICENSE", "Name", "Place", "Date", "of", "Birth", "Blood", "Type", "Sex", "Address",
                "Occupation", "Diterbitkan", "Oleh", "Issued", "by",
            ]
            .map(labelForm))

        /// Uppercase, with the letters recognition mixes up made one, so "Tgi" matches "Tgl".
        private static func labelForm(_ word: String) -> String {
            String(
                word.uppercased().map { letter in
                    "LI1|".contains(letter) ? "L" : letter == "0" ? "O" : letter
                })
        }

        private static func mask(line: String) -> String {
            var masked = ""
            var word = ""
            func flush() {
                masked += labelWords.contains(labelForm(word)) ? word : String(word.map(mask(letter:)))
                word = ""
            }
            for character in line {
                // Digits stay in a word, so a misread label like "N1K" is still compared whole.
                if character.isLetter || character.isNumber || character == "|" {
                    word.append(character)
                } else {
                    flush()
                    masked.append(character)
                }
            }
            flush()
            return masked
        }

        private static func mask(letter: Character) -> Character {
            if letter.isNumber { return "9" }
            if letter.isLetter { return letter.isLowercase ? "a" : "A" }
            return letter
        }
    }
#endif
