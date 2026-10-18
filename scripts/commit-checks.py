#!/usr/bin/env python3
# The checks a linter can't do, run by the git hooks (CONTRIBUTING.md, Setup):
#   python3 scripts/commit-checks.py staged          what the commit adds (pre-commit)
#   python3 scripts/commit-checks.py staged --all    every tracked file, every line (by hand)
#   python3 scripts/commit-checks.py message <file>  the commit message (commit-msg)
# Messages name a file and line, never a number that might be a real NIK.

import datetime
import os
import re
import subprocess
import sys

# 16 digits in a row (or more), or 4-4-4-4 split by spaces, dots or dashes, as a NIK can be written or read.
SIXTEEN_DIGITS = re.compile(r'(?<!\d)(?:\d{16,}|\d{4}[ .-]\d{4}[ .-]\d{4}[ .-]\d{4})(?!\d)')
# A path into the private docs/ folder, nested ones included.
DOCS_PATH = re.compile(r'(?<![\w.-])docs/')
# Files that name docs/ to guard it.
NAMES_DOCS_ON_PURPOSE = {'.gitignore', 'scripts/hooks/pre-commit', 'scripts/commit-checks.py'}
CREATED_BY = re.compile(r'^//  Created by (.+) on (\d{1,2})/(\d{1,2})/(\d{2})\.$', re.M)
# A disable of unchecked_sendable must be for the next, this or previous line and give a reason.
DISABLE = re.compile(r'swiftlint:disable(?::(next|this|previous))?\s+(.*)')
AI_COAUTHOR = re.compile(r'^co-authored-by:.*\b(claude|copilot|gpt|chatgpt|gemini|openai|anthropic)\b', re.I | re.M)
AI_LINES = re.compile(r'generated with|the claude app', re.I)


def git(*args, check=True):
    return subprocess.run(['git', '-c', 'core.quotePath=false', *args], capture_output=True, text=True,
                          check=check).stdout


def number_problem(text):
    """Why a line's 16-digit number can't be committed, or None."""
    for match in SIXTEEN_DIGITS.finditer(text):
        digits = re.sub(r'\D', '', match.group(0))
        # Test NIKs start with 00; masked text turns every digit into one.
        if not digits.startswith('00') and len(set(digits)) > 1:
            return "a 16-digit number that doesn't start with 00 (test NIKs do; real ones never belong here)"
    return None


def changed_lines(all_files):
    """(path, line number, text) for every added line, or every line of every tracked text file."""
    if all_files:
        for path in git('ls-files', '-z').split('\0'):
            if not path or not os.path.isfile(path):
                continue
            try:
                lines = open(path, encoding='utf-8').read().splitlines()
            except UnicodeDecodeError:
                continue
            for number, text in enumerate(lines, 1):
                yield path, number, text
        return
    binary = {fields[2] for fields in (entry.split('\t') for entry in
              git('diff', '--cached', '--numstat', '--diff-filter=ACMR').splitlines()) if fields[0] == '-'}
    for path in git('diff', '--cached', '--name-only', '-z', '--diff-filter=ACMR').split('\0'):
        if not path or path in binary:
            continue
        number = 0
        in_hunk = False
        for line in git('diff', '--cached', '-U0', '--no-color', '--no-ext-diff', '--', path).splitlines():
            if line.startswith('@@'):
                number = int(re.search(r'\+(\d+)', line).group(1))
                in_hunk = True
            elif in_hunk and line.startswith('+'):
                yield path, number, line[1:]
                number += 1


def header_problems(all_files):
    """An added Swift file's header names the Mac user, as Xcode does, and no future date."""
    if all_files:
        return []
    added = [path for path in git('diff', '--cached', '--name-only', '-z', '--diff-filter=A').split('\0')
             if path.endswith('.swift')]
    if not added:
        return []
    author = subprocess.run(['id', '-F'], capture_output=True, text=True).stdout.strip()
    if not author:
        return ["can't read the Mac user's full name (id -F), which Xcode writes in headers"]
    problems = []
    today = datetime.date.today()
    for path in added:
        match = CREATED_BY.search(git('show', f':{path}'))
        if not match:
            continue  # SwiftLint's file_header reports a missing or malformed header
        name, day, month, year = match.group(1), *map(int, match.group(2, 3, 4))
        if name != author:
            problems.append(f'{path}: "Created by {name}", but Xcode would write "{author}"')
        try:
            created = datetime.date(2000 + year, month, day)
        except ValueError:
            problems.append(f'{path}: the header date {day}/{month}/{year} is not a date')
            continue
        if created > today:
            problems.append(f'{path}: the header date {day}/{month}/{year} is after today; take it from the clock')
    return problems


def staged(all_files):
    problems = []
    if not all_files and git('symbolic-ref', '--short', '-q', 'HEAD', check=False).strip() == 'main':
        problems.append('this is main: commit on a branch, and merge through a pull request (CONTRIBUTING.md)')
    for path, number, text in changed_lines(all_files):
        reason = number_problem(text)
        if reason:
            problems.append(f'{path}:{number}: {reason}')
        if path not in NAMES_DOCS_ON_PURPOSE and DOCS_PATH.search(text):
            problems.append(f"{path}:{number}: points into the private docs/ folder, which readers can't open")
        disable = DISABLE.search(text) if path.endswith('.swift') else None
        if disable:
            scope, rest = disable.groups()
            rules = rest.split(' - ')[0].split()
            if 'unchecked_sendable' in rules or 'all' in rules:
                if scope is None:
                    problems.append(f'{path}:{number}: unchecked_sendable can only be disabled for one line')
                elif ' - ' not in rest or not rest.split(' - ', 1)[1].strip():
                    problems.append(f'{path}:{number}: disabling unchecked_sendable needs " - <reason>"')
    problems += header_problems(all_files)
    return problems


def contributing_list(label):
    for line in open('CONTRIBUTING.md', encoding='utf-8'):
        if line.startswith(f'- **{label}:**'):
            return set(re.findall(r'`([a-z-]+)`', line.split('.')[0] if label == 'Scopes' else line))
    raise SystemExit(f'commit-checks: CONTRIBUTING.md has no "{label}" line')


def message(path):
    raw = open(path, encoding='utf-8').read()
    # What git will keep: no text below the scissors line that -v adds, and no comment lines.
    char = git('config', '--get', 'core.commentChar', check=False).strip() or '#'
    raw = raw.split(f'{char} ------------------------ >8 ------------------------')[0]
    text = subprocess.run(['git', '-c', f'core.commentChar={char}', 'stripspace', '--strip-comments'],
                          input=raw, capture_output=True, text=True, check=True).stdout
    lines = text.splitlines()
    subject = lines[0].strip() if lines else ''
    problems = []
    if not subject:
        return ['the message is empty']
    passes_format = re.match(r'^(Merge |Revert "|(fixup|squash|amend)! )', subject)
    if not passes_format:
        types, scopes = contributing_list('Types'), contributing_list('Scopes')
        match = re.match(r'^([a-z]+)(?:\(([a-z-]+)\))?!?: (\S.*)$', subject)
        if not match:
            problems.append(f'the subject isn\'t "type(scope): subject" (CONTRIBUTING.md): {subject}')
        else:
            kind, scope, _ = match.groups()
            if kind not in types:
                problems.append(f'"{kind}" isn\'t a type in CONTRIBUTING.md: {", ".join(sorted(types))}')
            if scope and scope not in scopes:
                problems.append(f'"{scope}" isn\'t a scope in CONTRIBUTING.md: {", ".join(sorted(scopes))}')
        if subject.endswith('.'):
            problems.append('the subject ends with a full stop')
        if len(subject) > 100:
            problems.append(f'the subject has {len(subject)} characters; at most 100, aiming for 72')
        elif len(subject) > 72:
            print(f'commit-msg: the subject has {len(subject)} characters; aim for 72 (CONTRIBUTING.md)', file=sys.stderr)
    if AI_COAUTHOR.search(text):
        problems.append('a Co-Authored-By line names an AI; commits carry no AI attribution')
    for number, line in enumerate(lines, 1):
        if AI_LINES.search(line):
            problems.append(f'line {number}: no "Generated with" lines, and public messages don\'t mention the Claude app')
        reason = number_problem(line)
        if reason:
            problems.append(f'line {number}: {reason}')
    return problems


def main():
    os.chdir(git('rev-parse', '--show-toplevel').strip())
    if len(sys.argv) >= 2 and sys.argv[1] == 'staged':
        problems, label = staged('--all' in sys.argv[2:]), 'pre-commit'
    elif len(sys.argv) == 3 and sys.argv[1] == 'message':
        problems, label = message(sys.argv[2]), 'commit-msg'
    else:
        print('usage: commit-checks.py staged [--all] | message <file>', file=sys.stderr)
        return 2
    if problems:
        print(f'{label}: refused:', file=sys.stderr)
        for problem in problems:
            print('  ' + problem, file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
