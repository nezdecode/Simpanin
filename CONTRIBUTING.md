# Contributing to Simpanin

Simpanin holds people's ID documents, so some rules here are stricter than in most projects. Please read them before you open a pull request.

## Setup

Install the hooks once per clone, and SwiftLint if you don't have it:

```sh
git config core.hooksPath scripts/hooks
brew install swiftlint
```

Before every commit, the hooks in `scripts/hooks` refuse:

- images and PDFs outside `Fixtures/Synthetic/`, and the private files the repository ignores;
- Swift files that fail swift-format or SwiftLint, or break the app's folder rules (CODING.md, section 1);
- a commit on `main`;
- a 16-digit number that isn't a test NIK, in the changes or the message;
- a new Swift file whose header doesn't name you, as Xcode does, or is dated after today (headers use d/M/yy);
- a path into the private notes folder in a public file;
- `unchecked_sendable` switched off for more than one line, or without ` - <reason>`;
- a message that isn't `type(scope): subject` (below), runs past 100 characters, or credits an AI.

Never skip them with `--no-verify`; if one is wrong, fix the check.

Two scripts run what the hooks can't:

```sh
scripts/test.sh                      # every test on the iOS 27 iPhone 17 simulator
scripts/test.sh --only SimpaninTests # one target, or Target/Class
scripts/install-device.sh            # build, and install on your iPhone only if the build succeeded
```

`test.sh` fails when no test ran, which `xcodebuild` reports as a success. Without the iOS 27 iPhone 17 simulator, name another with `SIMPANIN_SIMULATOR=<id>`. `install-device.sh` lets Xcode renew a provisioning profile or register your iPhone in your developer account; with several iPhones, name one with `SIMPANIN_DEVICE=<udid>`. Piping a script into `tail` hides its exit status, so check the last lines it prints.

## Privacy

- No network code, analytics or crash reporting.
- The only dependency is [swift-crypto](https://github.com/apple/swift-crypto), and only its `Crypto` product. Open an issue before adding anything else.
- Never use real document data, in code, tests, fixtures, logs or issues. Test NIKs start with `00`, a province code no real region has.
- Images and PDFs only go under `Fixtures/Synthetic/`.
- Don't log field values, NIKs, names, keys or file contents. If the app really has to log something that might hold data, use `os.Logger` with `.private`.

## Code

How code is written here (structure, naming, SwiftUI patterns, reuse, tests, style and comments) is in [CODING.md](CODING.md). Read it before your first pull request.

## Commits

Commit messages follow [Conventional Commits](https://www.conventionalcommits.org): `type(scope): subject`, for example `fix(lock): keep the vault locked when the phone locks during the prompt`.

- **Types:** `feat` (something new for the user), `fix` (a bug), `test` (tests only), `refactor` (no change in behaviour), `docs`, `style` (formatting), `build` (project, signing, entitlements), `ci`, `chore`.
- **Scopes:** `vaultcore`, `parsers` (the Parsers target in the VaultCore package), `keychain`, `lock` (the lock engine in `Platform/Lock/`), `features` (anything in `Features/`), `debug`, `app` (anything else in the app target). Older commits use `screens` for what's now `features`. Leave the scope out when a change spans several.
- **Subject:** imperative and lowercase, no full stop. Aim for 72 characters; the hook warns past that and refuses past 100.
- **Body:** say why, when it isn't obvious. Break lines only where you mean a break, like a new paragraph or a separate point. Don't break inside a sentence to keep lines short: GitHub keeps those breaks, and the text turns choppy.
- **Breaking changes:** a change to the on-disk format, a key derivation label, an associated-data string or a Keychain value gets a `!` after the type and a `BREAKING CHANGE:` footer. These need a migration and a fixture test (see Formats in CODING.md).

Keep moves and reformatting in their own commits, separate from changes in behaviour, so each diff is easy to review.

## Branches and pull requests

Don't commit to `main`. Each piece of work gets its own branch, named `type/scope-topic` with the same types and scopes as commits, like `feat/parsers-sim` or `fix/vaultcore-flush`. When a branch holds several kinds of commits, name it after its main purpose. Branches merged before 15 Oct 2026 used `scope/topic`. Keep the small commits on that branch, then open a pull request into `main` that says what changed and which tests you ran.

Merge with **Create a merge commit**. Don't squash or rebase: notes and reviews refer to commits by their hash, and both of those create new hashes.
