#!/bin/bash
# Runs the commit hooks' checks on a pull request: each commit's message, the lines and files it adds, and
# every tracked file:
#   scripts/ci-checks.sh <base> <head>       for example: scripts/ci-checks.sh main HEAD
# The workflow in .github/workflows/checks.yml runs it, so a contributor without the hooks is still checked.
# Each commit is read on its own: one can remove what another added, but the merge keeps both in history.
# Not checked here: a new Swift file's header name and date, which the pre-commit hook checks.
set -euo pipefail
cd "$(dirname "$0")/.."

base="${1:?usage: scripts/ci-checks.sh <base> <head>}"
head="${2:?usage: scripts/ci-checks.sh <base> <head>}"
failed=0

# The same patterns as scripts/hooks/pre-commit: scans and the private files never belong in the repository.
refused_files() {
  local paths="$1" label="$2" bad private
  bad=$(printf '%s\n' "$paths" | grep -iE '\.(jpe?g|png|heic|pdf)$' | grep -v '^Fixtures/Synthetic/' || true)
  if [ -n "$bad" ]; then
    echo "ci-checks: $label: images or PDFs outside Fixtures/Synthetic/:" >&2
    echo "$bad" | sed 's/^/  /' >&2
    failed=1
  fi
  private=$(printf '%s\n' "$paths" | grep -E '^(docs/|\.claude/|CLAUDE\.md$)' || true)
  if [ -n "$private" ]; then
    echo "ci-checks: $label: private files (docs/, .claude/, CLAUDE.md):" >&2
    echo "$private" | sed 's/^/  /' >&2
    failed=1
  fi
}

# On its own line, so a base that doesn't exist stops the script instead of checking no commits.
commits=$(git rev-list --reverse "$base..$head")
message=$(mktemp)
trap 'rm -f "$message"' EXIT
for commit in $commits; do
  git log -1 --format=%B "$commit" > "$message"
  python3 scripts/commit-checks.py message "$message" || failed=1
  python3 scripts/commit-checks.py commit "$commit" || failed=1
  refused_files "$(git diff-tree --root --no-commit-id -r --name-only -z --diff-filter=ACMR "$commit" | tr '\0' '\n')" \
    "commit $(git rev-parse --short "$commit")"
done

# Numbers that might be NIKs, paths into docs/, the private specification by name, unchecked_sendable,
# Release's bundle id and groups.
python3 scripts/commit-checks.py staged --all || failed=1
# The Release identity check guards every user's vault, so it's tested too.
python3 scripts/test-commit-checks.py || failed=1
refused_files "$(git ls-files -z | tr '\0' '\n')" "the tree"
python3 scripts/check-folder-rules.py || failed=1

if [ "$failed" -ne 0 ]; then
  echo "ci-checks: refused (see above)" >&2
  exit 1
fi
echo "ci-checks: passed"
