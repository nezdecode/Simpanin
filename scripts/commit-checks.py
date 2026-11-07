#!/usr/bin/env python3
# The checks a linter can't do, run by the git hooks (CONTRIBUTING.md, Setup):
#   python3 scripts/commit-checks.py staged          what the commit adds (pre-commit)
#   python3 scripts/commit-checks.py staged --all    every tracked file, every line (by hand)
#   python3 scripts/commit-checks.py message <file>  the commit message (commit-msg)
#   python3 scripts/commit-checks.py commit <sha>    what one commit adds (scripts/ci-checks.sh)
# Messages name a file and line, never a number that might be a real NIK.

import datetime
import os
import re
import subprocess
import sys

# 16 or more digits with at most one space, dot or dash between them: a NIK however it's written or read
# (0012345678900001, 0012 3456 7890 0001, 001234 567890 0001, 00.12.34.567890.0001).
SIXTEEN_DIGITS = re.compile(r'(?<!\d)\d(?:[ .-]?\d){15,}(?!\d)')
# Hashes and UUIDs are left out first: their digits aren't numbers.
UUID = re.compile(r'\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b')
HEX_HASH = re.compile(r'\b(?=[0-9a-fA-F]*[a-fA-F])[0-9a-fA-F]{20,}\b')
# A path into the private docs/ folder, nested ones included; a URL with /docs/ in it is someone else's.
DOCS_PATH = re.compile(r'(?<![\w./:-])docs/')
# The private design doc by name, however it's spelled; public code says the rule itself instead. A name split
# across two lines isn't seen, as the checks read one line at a time.
DESIGN_DOC = re.compile(r'design[\s_\u2013-]*doc', re.I)
# Files that name docs/ to guard it.
NAMES_DOCS_ON_PURPOSE = {'.gitignore', 'scripts/hooks/pre-commit', 'scripts/commit-checks.py', 'scripts/ci-checks.sh'}
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
    text = HEX_HASH.sub(' ', UUID.sub(' ', text))
    for match in SIXTEEN_DIGITS.finditer(text):
        digits = re.sub(r'\D', '', match.group(0))
        # Test NIKs start with 00; masked text turns every digit into one.
        if not digits.startswith('00') and len(set(digits)) > 1:
            return "a 16-digit number that doesn't start with 00 (test NIKs do; real ones never belong here)"
    return None


def changed_lines(all_files, commit=None):
    """(path, line number, text) for every line added by the staged changes or by one commit, or every line
    of every tracked text file."""
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
    diff = ['diff', '--cached'] if commit is None else ['diff-tree', '--root', '--no-commit-id', '-r', commit]
    binary = {fields[2] for fields in (entry.split('\t') for entry in
              git(*diff, '--numstat', '--diff-filter=ACMR').splitlines()) if fields[0] == '-'}
    for path in git(*diff, '--name-only', '-z', '--diff-filter=ACMR').split('\0'):
        if not path or path in binary:
            continue
        number = 0
        in_hunk = False
        for line in git(*diff, '-p', '-U0', '--no-color', '--no-ext-diff', '--', path).splitlines():
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
            problems.append(f'{path}: the header date {day}/{month}/{year} is not a date; headers use d/M/yy')
            continue
        if created > today:
            problems.append(f'{path}: the header date {day}/{month}/{year} is after today; take it from the clock')
    return problems


PROJECT = 'Simpanin.xcodeproj/project.pbxproj'
# What the App Store app is known by. Changing one after release orphans every vault, its key or its projection,
# so Release keeps these whatever Debug uses. The team is in it because its prefix is part of the Keychain group.
RELEASE_SETTINGS = {
    'PRODUCT_BUNDLE_IDENTIFIER': 'com.inez.Simpanin',
    'SIMPANIN_APP_GROUP': 'group.com.inez.Simpanin',
    'SIMPANIN_KEYCHAIN_GROUP': 'simpanin.vault',
    'INFOPLIST_KEY_CFBundleDisplayName': 'Simpanin',
    'CODE_SIGN_ENTITLEMENTS': 'Config/Simpanin.entitlements',
    'DEVELOPMENT_TEAM': 'NLM7SY7FHH',
}
# Every other configuration needs its own of these, or a development build reaches the App Store app's vault.
OWN_IN_EVERY_BUILD = ['PRODUCT_BUNDLE_IDENTIFIER', 'SIMPANIN_APP_GROUP', 'SIMPANIN_KEYCHAIN_GROUP']
# KEY = value; or "KEY[sdk=iphoneos*]" = value; with the value quoted or not.
BUILD_SETTING = re.compile(r'^\s*"?(\w+)(\[[^\]]*\])?"? = "?([^";]*)"?;$', re.M)
# Both files take the groups from those settings, so they can't drift from each other or from Release.
READS_THE_GROUPS = {
    'Config/Info.plist': ['<string>$(SIMPANIN_APP_GROUP)</string>',
                          '<string>$(AppIdentifierPrefix)$(SIMPANIN_KEYCHAIN_GROUP)</string>'],
    'Config/Simpanin.entitlements': ['<string>$(SIMPANIN_APP_GROUP)</string>',
                                     '<string>$(AppIdentifierPrefix)$(SIMPANIN_KEYCHAIN_GROUP)</string>'],
}
BUILD_CONFIGURATION = re.compile(
    r'/\* (\w+) \*/ = \{\s*isa = XCBuildConfiguration;\s*buildSettings = \{(.*?)\n\t\t\t\};\s*name = (\w+);', re.S)


def release_identity_problems(all_files):
    """The app's Release configuration keeps the App Store app's identity, and no other configuration shares it."""
    def read(path):
        if not all_files:
            return git('show', f':{path}', check=False)
        try:
            return open(path, encoding='utf-8').read()
        except FileNotFoundError:
            return ''

    problems = []
    # The app's configurations are the ones built from Config/Info.plist; the test targets have none.
    builds = {}
    for _, block, name in BUILD_CONFIGURATION.findall(read(PROJECT)):
        settings = BUILD_SETTING.findall(block)
        if ('INFOPLIST_FILE', '', 'Config/Info.plist') in settings:
            builds[name] = settings
    if 'Release' not in builds:
        problems.append(f"{PROJECT}: can't find the app's Release configuration (INFOPLIST_FILE = Config/Info.plist)")
        return problems
    for name, settings in builds.items():
        # An SDK or architecture variant would replace the value for some builds only, out of sight of this check.
        for key, condition, _ in settings:
            if condition and key in RELEASE_SETTINGS:
                problems.append(f'{PROJECT}: {name} sets {key}{condition}; give it one value for every build')
    release = {key: value for key, condition, value in builds['Release'] if not condition}
    for key, value in RELEASE_SETTINGS.items():
        if release.get(key) != value:
            problems.append(f'{PROJECT}: Release must keep {key} = {value}; the App Store app is known by it')
    for name, settings in builds.items():
        if name == 'Release':
            continue
        values = {key: value for key, condition, value in settings if not condition}
        if values.get('CODE_SIGN_ENTITLEMENTS') != RELEASE_SETTINGS['CODE_SIGN_ENTITLEMENTS']:
            problems.append(f'{PROJECT}: {name} must sign with Config/Simpanin.entitlements, which reads the groups')
        for key in OWN_IN_EVERY_BUILD:
            if not values.get(key):
                problems.append(f'{PROJECT}: {name} needs its own {key}')
            elif values[key] == RELEASE_SETTINGS[key]:
                problems.append(f"{PROJECT}: {name} has Release's {key}, so it would reach the App Store app's vault")
    for path, needed in READS_THE_GROUPS.items():
        text = read(path)
        for line in needed:
            if line not in text:
                problems.append(f'{path}: must read {line}, so Debug and Release each get their own group')
        if re.search(r'group\.com\.inez|simpanin\.vault', text):
            problems.append(f'{path}: names a group itself; take it from SIMPANIN_APP_GROUP or SIMPANIN_KEYCHAIN_GROUP')
    return problems


def staged(all_files):
    problems = []
    if not all_files and git('symbolic-ref', '--short', '-q', 'HEAD', check=False).strip() == 'main':
        problems.append('this is main: commit on a branch, and merge through a pull request (CONTRIBUTING.md)')
    problems += line_problems(changed_lines(all_files))
    problems += header_problems(all_files)
    problems += release_identity_problems(all_files)
    return problems


def line_problems(lines):
    problems = []
    for path, number, text in lines:
        reason = number_problem(text)
        if reason:
            problems.append(f'{path}:{number}: {reason}')
        if path not in NAMES_DOCS_ON_PURPOSE and DOCS_PATH.search(text):
            problems.append(f"{path}:{number}: points into the private docs/ folder, which readers can't open")
        if path != 'scripts/commit-checks.py' and DESIGN_DOC.search(text):
            problems.append(f"{path}:{number}: names the private design doc; say the rule itself instead")
        disable = DISABLE.search(text) if path.endswith('.swift') else None
        if disable:
            scope, rest = disable.groups()
            rules = rest.split(' - ')[0].split()
            # custom_rules and all switch unchecked_sendable off too.
            if {'unchecked_sendable', 'custom_rules', 'all'} & set(rules):
                if scope is None:
                    problems.append(f'{path}:{number}: unchecked_sendable can only be disabled for one line')
                elif ' - ' not in rest or not rest.split(' - ', 1)[1].strip():
                    problems.append(f'{path}:{number}: disabling unchecked_sendable needs " - <reason>"')
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
    # With -m, git keeps lines starting with the comment character, so the content checks read them too.
    raw_lines = raw.splitlines()
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
            # Digits masked: a refused subject is printed, and it mustn't show a number that could be a NIK.
            shown = re.sub(r'\d', '9', subject)
            problems.append(f'the subject isn\'t "type(scope): subject" (CONTRIBUTING.md): {shown}')
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
    if AI_COAUTHOR.search(raw):
        problems.append('a Co-Authored-By line names an AI; commits carry no AI attribution')
    for number, line in enumerate(raw_lines, 1):
        if DESIGN_DOC.search(line):
            problems.append(f'line {number}: names the private design doc; say what it decided instead')
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
    elif len(sys.argv) == 3 and sys.argv[1] == 'commit':
        # A later commit can remove what an earlier one added, but a merge commit keeps both in history.
        problems, label = line_problems(changed_lines(False, sys.argv[2])), f'commit {sys.argv[2][:7]}'
    else:
        print('usage: commit-checks.py staged [--all] | message <file> | commit <sha>', file=sys.stderr)
        return 2
    if problems:
        print(f'{label}: refused:', file=sys.stderr)
        for problem in problems:
            print('  ' + problem, file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
