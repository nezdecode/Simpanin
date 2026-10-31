#!/bin/bash
# Runs the commit hooks' checks on a pull request, over every tracked file and each commit's message:
#   scripts/ci-checks.sh <base> <head>       for example: scripts/ci-checks.sh main HEAD
# The workflow in .github/workflows/checks.yml runs it, so a contributor without the hooks is still checked.
# The hooks see only what a commit adds; this reads the whole tree, which holds everything a branch added.
# Not checked here: a new file's header name, which needs the Mac user's name (the hook checks it).
set -euo pipefail
cd "$(dirname "$0")/.."

base="${1:?usage: scripts/ci-checks.sh <base> <head>}"
head="${2:?usage: scripts/ci-checks.sh <base> <head>}"
failed=0

# Numbers that might be NIKs, paths into docs/, the private specification by name, unchecked_sendable.
python3 scripts/commit-checks.py staged --all || failed=1

message=$(mktemp)
trap 'rm -f "$message"' EXIT
for commit in $(git rev-list --reverse "$base..$head"); do
  git log -1 --format=%B "$commit" > "$message"
  if ! python3 scripts/commit-checks.py message "$message"; then
    echo "ci-checks: the message of $(git rev-parse --short "$commit") (above)" >&2
    failed=1
  fi
done

# The same patterns as scripts/hooks/pre-commit: scans and the private files never belong in the repository.
bad=$(git ls-files | grep -iE '\.(jpe?g|png|heic|pdf)$' | grep -v '^Fixtures/Synthetic/' || true)
if [ -n "$bad" ]; then
  echo "ci-checks: images or PDFs outside Fixtures/Synthetic/:" >&2
  echo "$bad" | sed 's/^/  /' >&2
  failed=1
fi
private=$(git ls-files | grep -E '^(docs/|\.claude/|CLAUDE\.md$)' || true)
if [ -n "$private" ]; then
  echo "ci-checks: private files (docs/, .claude/, CLAUDE.md):" >&2
  echo "$private" | sed 's/^/  /' >&2
  failed=1
fi

python3 scripts/check-folder-rules.py || failed=1

if [ "$failed" -ne 0 ]; then
  echo "ci-checks: refused (see above)" >&2
  exit 1
fi
echo "ci-checks: passed"
