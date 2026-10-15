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

How code is written here (structure, naming, SwiftUI patterns, reuse, tests, style and comments) is in [CODING.md](CODING.md). Read it before your first pull request.

## Commits

Commit messages follow [Conventional Commits](https://www.conventionalcommits.org): `type(scope): subject`, for example `fix(lock): keep the vault locked when the phone locks during the prompt`.

- **Types:** `feat` (something new for the user), `fix` (a bug), `test` (tests only), `refactor` (no change in behaviour), `docs`, `style` (formatting), `build` (project, signing, entitlements), `ci`, `chore`.
- **Scopes:** `vaultcore`, `parsers` (the Parsers target in the VaultCore package), `keychain`, `lock`, `screens`, `debug`, `app` (anything else in the app target). Leave the scope out when a change spans several.
- **Subject:** imperative and lowercase, no full stop, at most about 72 characters.
- **Body:** say why, when it isn't obvious. Break lines only where you mean a break, like a new paragraph or a separate point. Don't break inside a sentence to keep lines short: GitHub keeps those breaks, and the text turns choppy.
- **Breaking changes:** a change to the on-disk format, a key derivation label, an associated-data string or a Keychain value gets a `!` after the type and a `BREAKING CHANGE:` footer. These need a migration and a fixture test (see Formats in CODING.md).

Keep moves and reformatting in their own commits, separate from changes in behaviour, so each diff is easy to review.

## Branches and pull requests

Don't commit to `main`. Each piece of work gets its own branch, named after it, like `app/part-4-screens` or `vaultcore/fix-flush`. Keep the small commits on that branch, then open a pull request into `main` that says what changed and which tests you ran.

Merge with **Create a merge commit**. Don't squash or rebase: notes and reviews refer to commits by their hash, and both of those create new hashes.
