# How we write code in Simpanin

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
- `Screens/`: one folder per screen or flow (`Library`, `RecentlyDeleted`, `Settings`, `OldVaults`, `LockCover`), each holding its views and the models behind them side by side. A file is named after its main type: `LibraryModel.swift` holds the `@Observable` model, `LibraryView.swift` its view.
- `Components/`: views and styles several screens use, like `IconBadge` and `FullWidthButtonStyle`. Check here before building a new one.
- `Extensions/`: extensions on system types, one file per type and purpose, named like `Date+Indonesian.swift`.
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
