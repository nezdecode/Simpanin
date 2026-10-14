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

## Architecture

Simpanin has two parts: a core that knows how to keep documents safe, and an app around it.

**VaultCore** (`Packages/VaultCore`) holds everything about storing documents: encryption, the file format, the order of writes, recovery and purging. It imports only Foundation and Crypto, so its tests run on a Mac without a simulator. It reaches the platform through small protocols (`KeyStore`, `VaultClock`, `FileProtector`) that the app implements. `VaultStore` is an actor and the only way in, and every change goes through its write order. If a piece of logic doesn't need UIKit, SwiftUI, the Keychain or Face ID, it probably belongs here.

**The app** (`Simpanin/`) is organised by topic at the top, and by screen inside `Screens/`:

- `App/`: the entry point, `RootView` (which switches between the lock cover and the app) and the build configuration.
- `Vault/`: the platform side of VaultCore (`KeychainKeyStore`, `DataProtectionFileProtector`) and `AppVault`, which creates the app's one `VaultStore` at launch.
- `Lock/`: `LockController`, the lock's state machine, `RecoveryMapping`, which decides what the user sees when opening fails, and the lock settings and checks every screen relies on.
- `Documents/`: how a document reads on screen: type names, colours and the expiry wording.
- `Screens/`: one folder per area (`Library`, `Settings`, `Recovery`), each holding its views and the models behind them side by side. A file is named after its main type: `LibraryModel.swift` holds the `@Observable` model, `LibraryView.swift` its view. `Shared/` holds the few pieces several screens use.
- `Debug/`: tools that only exist in DEBUG builds.

VaultCore keeps its public types in `Models.swift` and everything it writes to disk in `Format.swift`, so a format change is easy to spot.

A few rules keep it that way:

- Views stay thin. They show state and pass on taps. State and logic live in `@MainActor @Observable` models, one per screen or flow.
- When a decision can be a pure function, make it one, like what to show for an error. Then it's tested without any UI.
- Models depend on small protocols (`VaultOpening`, `DocumentStoring` and so on) rather than on `VaultStore` itself, so tests can use stand-ins. Add a protocol when a test needs one, not before.
- There is one `VaultStore` per vault folder. Don't create another one for the real vault.
- Calls that can block, like the Keychain while a prompt is up, run off the actor that calls them.
- Every text the user sees lives in `Localizable.xcstrings` under a short key.
- DEBUG-only code stays inside `#if DEBUG`, in `Debug/` where possible.

Tests follow the same split. VaultCore is tested with `swift test`. App logic is tested in `SimpaninTests` with stand-ins, kept in `SimpaninTests/Support/`. Screens are tested in `SimpaninUITests` on a throwaway vault (the `-SimpaninUITest` launch argument), finding elements by accessibility identifier rather than by layout. What only a real phone can show, like Face ID and file protection classes, goes through the DEBUG device checks screen.

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

Commit messages follow [Conventional Commits](https://www.conventionalcommits.org): `type(scope): subject`, for example `fix(lock): keep the vault locked when the phone locks during the prompt`.

- **Types:** `feat` (something new for the user), `fix` (a bug), `test` (tests only), `refactor` (no change in behaviour), `docs`, `style` (formatting), `build` (project, signing, entitlements), `ci`, `chore`.
- **Scopes:** `vaultcore`, `keychain`, `lock`, `screens`, `debug`, `app` (anything else in the app target). Leave the scope out when a change spans several.
- **Subject:** imperative and lowercase, no full stop, at most about 72 characters.
- **Body:** say why, when it isn't obvious. Break lines only where you mean a break, like a new paragraph or a separate point. Don't break inside a sentence to keep lines short: GitHub keeps those breaks, and the text turns choppy.
- **Breaking changes:** a change to the on-disk format, a key derivation label, an associated-data string or a Keychain value gets a `!` after the type and a `BREAKING CHANGE:` footer. These need a migration and a fixture test (see Code).

Keep moves and reformatting in their own commits, separate from changes in behaviour, so each diff is easy to review.

## Branches and pull requests

Don't commit to `main`. Each piece of work gets its own branch, named after it, like `app/part-4-screens` or `vaultcore/fix-flush`. Keep the small commits on that branch, then open a pull request into `main` that says what changed and which tests you ran.

Merge with **Create a merge commit**. Don't squash or rebase: notes and reviews refer to commits by their hash, and both of those create new hashes.
