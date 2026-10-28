# How we write code in Simpanin

This is the guide for writing code here: where things go, how they're named, how they're built and how they're tested. `CONTRIBUTING.md` covers the process around it (setup, privacy, commits, pull requests). Most rules come from something that went wrong or was fixed in this repository; where a pull request shows why, it's named.

## 1. Where code goes

Simpanin has two parts: a core that keeps documents safe, and an app around it.

**VaultCore** (`Packages/VaultCore`) holds everything about storing documents: encryption, the file format, the order of writes, recovery and purging. It imports only Foundation and Crypto, so its tests run on a Mac without a simulator. It reaches the platform through small protocols (`KeyStore`, `VaultClock`, `FileProtector`) that the app implements. `VaultStore` is an actor and the only way in, and every change goes through its write order. The document model is in `Models.swift`; everything it writes to disk is in `Format.swift`. If logic doesn't need UIKit, SwiftUI, the Keychain or Face ID, it probably belongs here.

**Parsers** (`Packages/VaultCore/Sources/Parsers`) turns recognised text into a document type and its fields, and marks what the user should check again, with every reason as a `CheckReason` code; the app turns the first into text. It's a separate target in the same package: it uses VaultCore's model, but VaultCore never depends on it. Text recognition stays in the app, so the parsers are tested on plain text on a Mac.

**The app** (`Simpanin/`) is organised by feature, around a few shared layers:

| Folder | Holds |
| --- | --- |
| `App/` | The entry point and `RootView`, which puts the features together, with `CoverWindow`, the window that covers every screen. |
| `Features/<Feature>/` | One folder per feature: something the user can name (`Library`, `Scan`, `Settings`, `Lock`), with its views and models side by side. |
| `Documents/` | How a document reads: `DocumentStyle`, `ExpiryText`, dates in Indonesian and on calendar days. |
| `Platform/` | The app's side of VaultCore and iOS: `Vault/` (`AppVault`, which creates the one `VaultStore`, the Keychain, file protection), `Lock/` (`LockController`, the engine that locks and unlocks, and the recovery table), `Logging/` and `System/` (build settings, system links). |
| `DesignSystem/` | Views, styles, texts and helpers that know nothing of the domain: no VaultCore, `Documents/` or feature types. |
| `Resources/` | The asset catalog (colours, icon) and the string catalog. |
| `Debug/` | DEBUG-only tools. |

Five rules keep the folders honest:

1. **A feature is something the user can name.** Its own screens and state live in its folder.
2. **Besides VaultCore, Parsers and system frameworks, a feature uses only `Platform/`, `Documents/`, `DesignSystem/`, and other features' entry points.** Today those are `LibraryView`, `RecentlyDeletedView` and `LibraryModel` (Library); `ScanFlowView`, `DocumentCamera.isSupported` and `DocumentCameraCache.clear()` (Scan); `SettingsView` (Settings); and `LockCoverView` (Lock). `App/` uses entry points too. `scripts/check-folder-rules.py` holds the checked list and runs before every commit, so a new entry point is added there and here. Anything else two features need goes to `DesignSystem/`, `Documents/` or `Platform/`.
3. **`DesignSystem/` holds views and styles with no knowledge of the domain, from their first use.** They never name a VaultCore, `Platform/`, `Documents/` or feature type, and SwiftLint rejects importing VaultCore or Parsers there. Texts with the app's words, like `ScreenText`, are fine: the rule is about types. A view that knows the domain stays in its feature; when two features need it, its look moves to `DesignSystem/` or the view moves to `Documents/`.
4. **There's no folder for extensions.** An extension sits beside its user or in its domain's folder; one that two or more features use goes to `DesignSystem/` (UI) or `Platform/` (system).
5. **`Platform/` knows nothing about features.** It reports the vault's state and errors; which screen shows is a feature's decision. (For now the recovery table and its texts still live with the lock engine in `Platform/Lock/`, until they're split.)

Below the features, the layers go one way: `Documents/` may use `Platform/`, `Platform/` and `DesignSystem/` use none of the others, and `App/` may use all of them. `Debug/` may reach anything and anything may reach it, inside `#if DEBUG`.

`scripts/check-folder-rules.py` checks these rules before every commit. It matches type names, so it doesn't see members added in extensions of system types (such as `Calendar.gregorianUTC`) or global functions; review catches those.

Tests follow the code. `SimpaninTests` mirrors the app's folders (`Platform/Lock/`, `Features/Library/` and so on), with shared stand-ins in `Support/`. VaultCore's tests are grouped by topic (`Store/`, `Durability/`, `Recovery/`, `Format/`), the parsers' by parser. `SimpaninUITests` has a class per screen (`LibraryUITests`, `ReviewUITests`), each built on `Support/UITestCase`, which is where helpers shared between screens go.

A few rules keep it that way:

- **There is one `VaultStore` per vault folder.** `AppVault` creates it at launch; nothing else creates one for the real vault.
- **DEBUG-only code stays inside `#if DEBUG`**, in `Debug/` where possible, so it can never reach a release build.

A folder grows subfolders by part of the feature, never by layer (`Models/`, `Views/`): when it passes about eight files and a part of it has at least three (`Library/Banner/`, `Scan/Review/`). The same rule applies again inside a part, at most two levels below the feature, and a part's main model and view stay at its root. The branch that takes a folder past the threshold splits it first, in a move-only commit, before adding its files.

### Architecture

The layout doesn't show layers, so the names and these rules do:

- **One `@MainActor @Observable` model per screen or flow, and a thin view.** The model holds state and logic; the view shows state and passes on taps (section 4).
- **Decisions are pure functions** (`ExpiryText`, `HiddenBanner`, `RecoveryMapping`), tested without UI.
- **Dependencies come in through `init`, as small protocols** (`DocumentStoring`, `VaultOpening`) rather than `VaultStore` itself, so tests can use stand-ins. Add a protocol when a test needs one, not before. No singletons of our own.
- **VaultCore is the only storage for documents.** Small app-side files that hold no document data, like the banner's hidden list, sit beside the projection and follow its rules.
- **App-wide services go through `Platform/`:** the Keychain, Face ID, file protection, the App Group and Keychain group from Info.plist, system links and logging. `App/` wires system events (the app's state, notifications, settings storage) into `Platform/`'s lock engine. A framework only one feature needs stays in that feature, behind a protocol when tests need a stand-in (Vision and VisionKit in `Features/Scan`, `TextRecognizer`).
- **Name suffixes replace layer folders:** `…Model`, `…View`, `…Row`, `…Card`.

## 2. Files and names

- **One main type per file, named after it.** `LibraryModel.swift`, `LibraryView.swift`, `DocumentTile.swift`. Types that belong to the main type stay with it, even when other files use them: the protocol it depends on (`VaultOpening` in `LockController.swift`), a value it returns or holds (`RecoveryScreen` from `RecoveryMapping`, `VaultLocations` in `AppVault.swift`). A type that is its own idea, or that several main types share, gets its own file (`VaultNotice`; `DocumentStoring` and `QuarantineStoring`, which several models depend on).
- **A screen's model ends in `Model`, its view in `View`.** A screen is `XModel` + `XView`. Objects every screen shares are named for their job: `LockController`, `AppVault`. Rows and parts of a screen are named for what they show: `OldVaultRow`, `ExpiryBanner`.
- **Extensions go in `Type+Purpose.swift`**, beside their user or in their domain's folder: `Documents/Date+Indonesian.swift`, `Platform/Logging/Logger+Simpanin.swift`.
- **Follow Apple's [API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/)** and use SwiftUI's own words: `systemImage` for an SF Symbol name, `onDelete` / `onRestore` for callbacks, `.roundedRectangle(cornerRadius:)` rather than a bare number.
- **American spelling in identifiers** (`tileColors`, `toneColor`), as in Apple's APIs. Comments and docs can use either.
- **Test files are named after what they test**: `ExpiryTextTests.swift` tests `ExpiryText`.

## 3. Swift

- **Swift 6 with complete strict concurrency.** If you think you need `@unchecked Sendable` or `nonisolated(unsafe)`, explain why in the pull request.
- **The app's default isolation is the main actor.** A pure helper that a nonisolated type calls needs `nonisolated`; the compiler tells you where.
- **Calls that can block run off the caller's actor**, like the Keychain while a Face ID prompt is up.
- **VaultCore imports only Foundation and Crypto, and Parsers only Foundation and VaultCore.** SwiftLint checks both.
- **Errors are handled, not swallowed.** Map them to what the user sees (`RecoveryMapping`) and log only their domain and code. `(try? load()) ?? []` turns a failure into an empty list, which tells someone storing their ID that it's gone. `try?` is fine only where failing really changes nothing, like removing a temporary file.

## 4. SwiftUI

**Views stay thin.** They show state and pass on taps. State and logic live in `@MainActor @Observable` models, one per screen or flow. Decisions that can be pure functions are pure functions (`ExpiryText`, `RecoveryContent.tone`), so they're tested without UI. A setting that has to be saved and applied is one call on the model (`LockController.setAutoLock`), not two steps in a view. And a stored setting is applied wherever its owner is created, not only where it changes: a launch once ignored the saved auto-lock choice, so Settings showed one time while the app used another (#9).

**A view never keeps its own copy of state that lives elsewhere.** `@State` is for what only the view knows, like a text field's draft. A stored setting or a model's value is read from the model each time: a copy in `@State` is taken once and goes stale, which made Settings show an old Kunci otomatis choice after it had been changed.

**Small views get only the data they show.** `ExpiryBanner(documents:today:onHide:)`, not the whole screen model. Callbacks are named for the event: `onHide`, `onDelete`, `onRestore`, `onDismiss`.

**Pick the right tool to reuse or customise:**

| You want to | Use | Example |
| --- | --- | --- |
| Restyle a system control | A style type (`ButtonStyle`, `PrimitiveButtonStyle`, `LabelStyle`) | `.buttonStyle(.prominent)` |
| Reuse a decoration | A `ViewModifier` with a `View` extension | `.noticeCard()` |
| Build new content | A `View` | `IconBadge` |
| Format a value | A `FormatStyle` | `date.formatted(.indonesianDate(timeZone:))` |
| Add a convenience to a system type | An extension | `Binding(isPresent:)`, `URL.appSettings` |

A style type built on a system style keeps what the system gives for free: pressed and disabled looks, Dynamic Type, iOS 26's glass. `ProminentButtonStyle` wraps `.borderedProminent` for that reason.

**Prefer what the platform already has.** Standard toolbar buttons, `Form`, `List`, swipe actions, `.byteCount(style: .file)`. Build our own only when the design needs something the system doesn't do.

**Design details that keep coming back:**

- Colours come from the asset catalog's generated symbols, `Color(.warning)`, never `Color("Warning")`: a typo then fails to compile instead of showing nothing. Every colour has a Dark Mode variant, and text keeps a contrast of at least 4.5:1 (white on the dark-mode accent didn't). A ground colour is never text: `Warning` is a notice card's ground and `OnWarning` its text, and "Periksa lagi" drawn in `Warning` was barely visible on a form row. `ColorContrastTests` checks the pairs that matter.
- A refusal and a mark look different. A refusal (`RefusalText`, red with a circled "!") is what has to change before an action works; a mark (`WarningText`, "Periksa lagi: <reason>", amber with a triangle) can be left as it is. A refusal replaces a mark, and VoiceOver reads either in the field's label.
- Every text the user sees is in `Localizable.xcstrings` under a short key. What the user typed and numbers use `Text(verbatim:)`, so they're never looked up as keys. DEBUG-only screens may use plain strings.
- Layouts work at accessibility text sizes (the list drops to one column).
- Decorative images are hidden from VoiceOver; the text next to them says what they mean.
- Elements that UI tests use get an `accessibilityIdentifier`.
- Move focus only after an alert or sheet has fully closed, never with a fixed delay. Focus set while one is still closing can be dropped.

## 5. Reuse

Before building a view, a style or a helper, check `DesignSystem/`, and the feature you're in. Extract a shared piece when it's used a second time, or when the design already has another screen that uses it. Not before: a shared piece with one user is harder to follow than the code it replaced.

## 6. Values

- **Identifiers of stored data, and the values they store, never change once a build has shipped**, because changing one orphans what's already stored. Two kinds:
  - **Constants in code, defined once**: the Keychain service (`KeychainKeyStore.service`), file and folder names (`VaultLocations`, `VaultStore.headerFileName`), settings keys, and the raw values an enum stores in the app (`AutoLock`'s cases spell theirs out, and a test pins them and their key, so renaming can't reset anyone's choice). VaultCore's JSON keys are pinned by the fixture tests instead (section 9).
  - **Build settings, read from Info.plist** (`AppConfiguration`) so they always match the entitlements: the Keychain access group and the App Group. A debug build may use its own values, but a configuration's values never change after it ships.
- **Everything else about the build comes from `Bundle.main`**, like the bundle identifier for the log subsystem.
- **Field keys** (`nik`, `name`, `birthDate`) are stored in every document too, so they never change either; a test pins each one. A key is named for what the value means, not for the document it came from, so `name` is the same key on a KTP, a SIM and a passport.
- **Document type ids** (`ktp`, `sim-a`) are stored in every vault and never renamed; only their display names change. They all live in VaultCore, in `DocumentType` (`Models.swift`), because VaultCore needs to know them too: reminders, which VaultCore plans, depend on which types are SIMs (`DocumentType.isSIM`, `simClasses`).
- **Calendar days are calendar days.** Expiry dates are `CalendarDate`s read in UTC (`Calendar.gregorianUTC`), so no time zone moves them.

## 7. Privacy and honesty in code

The privacy rules in `CONTRIBUTING.md` apply everywhere. In code that means:

- Log through `Logger.launch` and friends, with `privacy: .public` only on an error's domain and code (`ErrorSummary`).
- A label or anything a user types never goes into `projection.json`, which is plaintext.
- Nothing on screen pretends to work. A row for a feature that doesn't exist yet stays out until it does.

## 8. Security and memory

Some of these describe features that aren't built yet (the document screen, sharing, copying a number). They're the rules for when they are.

- **Decrypted data lives in memory only while it's on screen.** Only the open document is decrypted. Its fields and pages are let go when its screen closes and when the vault locks, and never kept in a cache, a static or a long-lived model. The one exception is the duplicate check on Simpan: it decrypts the fields of saved documents that could match (the same type, or any SIM when either has no class), never their pages, compares them in memory and doesn't keep them.
- **Nothing decrypted touches the disk**: no image cache, no `URLCache`. Where a system API needs a file (sharing a PDF, Quick Look), it goes in its own folder in `tmp`, deleted when the share sheet or preview closes and again at the next launch, in case the app was stopped in between. Which viewers make their own copy is still to be checked on a device.
- **Secrets live in the Keychain only**, never in `UserDefaults`, a file or a log.
- **A copied number is local-only and expires** after about 60 seconds, so it doesn't reach other devices or stay on the clipboard.
- **The screen is covered** when the app leaves the foreground and while the screen is recorded or mirrored (`LockController.contentHidden`, built).
- **Work tied to a view's lifetime uses `.task`**, which SwiftUI cancels when the view goes away. A button action starting a `Task` is fine. A closure that a model keeps must not capture `self` strongly when that makes a cycle; prefer passing values in.
- **No new dependency** without asking first (see `CONTRIBUTING.md`); every dependency can read what the app reads.

## 9. Formats

Once a format ships, it stays. Don't change a key derivation label, an associated-data string, a Keychain flag or the file layout without a migration and a new fixture test. The committed vaults in `Fixtures/Synthetic/` must always open. A format change gets a `!` and a `BREAKING CHANGE:` footer in its commit.

## 10. Tests

- **Test first, and watch it fail.** Write a stub that compiles, run the test against it, then implement. A test that never failed may test nothing.
- **For logic that guards data, break the code on purpose** (skip a save, ignore an argument, leak a value) and check a test fails. Then put it back.
- **Tests never wait forever.** Anything that waits for a gate has a timeout. Use `try #require` before indexing into a result.
- **VaultCore** and **Parsers** are tested with `swift test` in `Packages/VaultCore`, on a Mac, no simulator. Parser tests use synthetic text only. **App logic** is tested in `SimpaninTests`, with the stand-ins in `Support/` for the models. **Screens** are tested in `SimpaninUITests` on a throwaway vault (`-SimpaninUITest`), finding elements by accessibility identifier rather than by layout.
- **The simulator isn't a phone.** Anything that touches system folders, file attributes, protection classes, the Keychain or Face ID also runs on a device before it's merged: the simulator once let the app change a folder that iOS refuses on a phone, and every launch failed (#11). The DEBUG device checks screen covers what can be checked by hand.
- **A refactor proves it changed nothing**: compare the code before and after (only names and headers may differ), run every test, and compare the UI test screenshots with main.

## 11. Style

swift-format handles layout (`.swift-format`); SwiftLint handles naming, size, file headers and the rules above that a tool can check (`.swiftlint.yml`): colours by name, VaultCore's file names outside VaultCore, hand-built date formats, `print` and friends, common British spellings in identifiers, `@unchecked Sendable` and `nonisolated(unsafe)` (an agreed one is disabled for its line, with the reason), a doc comment with a blank line under it, VaultCore or Parsers imported into `DesignSystem/`, and `PageReading` or `VaultStore` named in `Features/Scan/`, which reads saved fields but never pages. The hooks check the rest before every commit (CONTRIBUTING.md, Setup). Before you commit:

```sh
swift format format -i -r Packages/VaultCore Simpanin SimpaninTests SimpaninUITests
swift format lint --strict -r Packages/VaultCore Simpanin SimpaninTests SimpaninUITests
swiftlint lint --strict
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

## 12. Comments

Add a comment when the code can't say it for itself: why something is done this way, a rule that has to keep holding, or a side effect nobody would guess. Keep it to a line or two, and write it the way you'd leave a note for a teammate. If a comment only repeats the function name or the code below it, leave it out.

## 13. Before you commit

1. Is this the simplest thing that works? What would you remove?
2. Is there already a component, extension or helper for it?
3. Do the names read like Apple's and SwiftUI's?
4. Can the logic be tested without UI, and is it?
5. Did the new test fail first?
6. What about empty, error, Dark Mode, large text and no passcode? VoiceOver reads everything on screen, including why something was refused.
7. Have you used the screen by hand, the way a user would? Every keyboard (including the number pad), sheet, picker and alert can be closed, nothing overlaps when the keyboard is up, and everything that can be tapped looks tappable.
8. Does it behave the same on a device as in the simulator?
9. Does it match the UI design, and does it keep the product's promise: private, and nothing shown as working before it does?
