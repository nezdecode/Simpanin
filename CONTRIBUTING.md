# Contributing to Simpanin

Simpanin holds people's ID documents, so some rules here are stricter than in most projects. Please read them before you open a pull request.

## Setup

Install the pre-commit hook once per clone, and SwiftLint if you don't have it:

```sh
git config core.hooksPath scripts/hooks
brew install swiftlint
```

The hook rejects images and PDFs outside `Fixtures/Synthetic/`, and Swift files that fail swift-format or SwiftLint.

## Privacy

- No network code, analytics or crash reporting.
- The only dependency is [swift-crypto](https://github.com/apple/swift-crypto), and only its `Crypto` product. Open an issue before adding anything else.
- Never use real document data, in code, tests, fixtures, logs or issues. Test NIKs start with `00`, a province code no real region has.
- Images and PDFs only go under `Fixtures/Synthetic/`.
- Don't log field values, NIKs, names, keys or file contents. If the app really has to log something that might hold data, use `os.Logger` with `.private`.

## Code

- Swift 6 language mode with complete strict concurrency. If you think you need `@unchecked Sendable` or `nonisolated(unsafe)`, explain why in the pull request.
- VaultCore imports only Foundation and Crypto. Keeping platform frameworks out is what lets its tests run on a Mac without a simulator. SwiftLint checks this.
- Once a format ships, it stays. Don't change a key derivation label, an associated-data string, a Keychain flag or the file layout without a migration and a new fixture test. The vault in `Fixtures/Synthetic/VaultV1` must always open.
- For VaultCore, write the test first and watch it fail before you fix the code.

## Style

swift-format handles layout (`.swift-format`). SwiftLint handles naming, size and file headers (`.swiftlint.yml`). Before you commit, run:

```sh
swift format format -i -r Packages/VaultCore && swiftlint lint --strict
```

Every Swift file starts with the header Xcode creates, followed by the license notice. `Package.swift` is the one exception, because its first line has to be `swift-tools-version`.

```swift
//
//  VaultStore.swift
//  VaultCore
//
//  Created by Your Name on 4/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
```

## Comments

Add a comment when the code can't say it for itself: why something is done this way, a rule that has to keep holding, or a side effect nobody would guess. Keep it to a line or two, and write it the way you'd leave a note for a teammate. If a comment only repeats the function name or the code below it, leave it out.

## Commits

Write a short subject in the imperative ("Add page reordering"), and a body that says why when it isn't obvious. Keep moves and reformatting in their own commits, separate from changes in behaviour, so each diff is easy to review.
