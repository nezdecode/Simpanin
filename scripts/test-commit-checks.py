#!/usr/bin/env python3
# Tests the Release identity check in scripts/commit-checks.py, which is the only guard on the App Store app's
# bundle id, groups and team. Each case changes a copy of the project, Info.plist or entitlements in a temporary
# folder, never the real files. Run by scripts/ci-checks.sh; by hand with:
#   python3 scripts/test-commit-checks.py

import importlib.util
import os
import shutil
import sys
import tempfile

sys.dont_write_bytecode = True
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
spec = importlib.util.spec_from_file_location('commit_checks', os.path.join(ROOT, 'scripts', 'commit-checks.py'))
checks = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checks)

PROJECT, INFO, ENTITLEMENTS = checks.PROJECT, 'Config/Info.plist', 'Config/Simpanin.entitlements'


def in_block(name, old, new):
    """Replaces old with new inside the app's configuration called name only."""
    def change(text):
        for match in checks.BUILD_CONFIGURATION.finditer(text):
            block = match.group(0)
            if match.group(3) == name and 'INFOPLIST_FILE = Config/Info.plist;' in block and old in block:
                return text[:match.start()] + block.replace(old, new, 1) + text[match.end():]
        raise AssertionError(f'{name} has no "{old}"')
    return change


def add_after(name, line, added):
    """Adds a line after one in the app's configuration called name, with the same indent."""
    return in_block(name, line, f'{line}\n\t\t\t\t{added}')


def replace(old, new):
    def change(text):
        assert old in text, f'no "{old}"'
        return text.replace(old, new, 1)
    return change


def remove(path):
    return lambda folder: os.remove(os.path.join(folder, path))


GROUP = '<string>$(SIMPANIN_APP_GROUP)</string>'
KEYCHAIN = '<string>$(AppIdentifierPrefix)$(SIMPANIN_KEYCHAIN_GROUP)</string>'

# (what changes, file, change, whether the check must refuse it)
CASES = [
    ('nothing', None, None, False),
    ('a quoted Release value', PROJECT,
     in_block('Release', 'SIMPANIN_KEYCHAIN_GROUP = simpanin.vault;', 'SIMPANIN_KEYCHAIN_GROUP = "simpanin.vault";'),
     False),
    ("Release's bundle id", PROJECT,
     in_block('Release', 'PRODUCT_BUNDLE_IDENTIFIER = com.inez.Simpanin;', 'PRODUCT_BUNDLE_IDENTIFIER = com.inez.X;'),
     True),
    ("Release's App Group", PROJECT,
     in_block('Release', 'SIMPANIN_APP_GROUP = group.com.inez.Simpanin;', 'SIMPANIN_APP_GROUP = group.com.inez.X;'),
     True),
    ("Release's Keychain group", PROJECT,
     in_block('Release', 'SIMPANIN_KEYCHAIN_GROUP = simpanin.vault;', 'SIMPANIN_KEYCHAIN_GROUP = simpanin.x;'), True),
    ("Release's name", PROJECT,
     in_block('Release', 'INFOPLIST_KEY_CFBundleDisplayName = Simpanin;',
              'INFOPLIST_KEY_CFBundleDisplayName = "Simpanin Dev";'), True),
    ("Release's team", PROJECT,
     in_block('Release', 'DEVELOPMENT_TEAM = NLM7SY7FHH;', 'DEVELOPMENT_TEAM = ABCDE12345;'), True),
    ("Release's entitlements file", PROJECT,
     in_block('Release', 'CODE_SIGN_ENTITLEMENTS = Config/Simpanin.entitlements;',
              'CODE_SIGN_ENTITLEMENTS = Config/Other.entitlements;'), True),
    ('an SDK variant of a group in Release', PROJECT,
     add_after('Release', 'SIMPANIN_APP_GROUP = group.com.inez.Simpanin;',
               '"SIMPANIN_APP_GROUP[sdk=iphoneos*]" = group.com.inez.X;'), True),
    ('an SDK variant of the bundle id in Debug', PROJECT,
     add_after('Debug', 'PRODUCT_BUNDLE_IDENTIFIER = com.inez.Simpanin.dev;',
               '"PRODUCT_BUNDLE_IDENTIFIER[sdk=iphoneos*]" = com.inez.Simpanin;'), True),
    ("Debug's entitlements file", PROJECT,
     in_block('Debug', 'CODE_SIGN_ENTITLEMENTS = Config/Simpanin.entitlements;',
              'CODE_SIGN_ENTITLEMENTS = Config/Other.entitlements;'), True),
    ("Debug with Release's bundle id", PROJECT,
     in_block('Debug', 'PRODUCT_BUNDLE_IDENTIFIER = com.inez.Simpanin.dev;',
              'PRODUCT_BUNDLE_IDENTIFIER = com.inez.Simpanin;'), True),
    ("Debug with Release's App Group", PROJECT,
     in_block('Debug', 'SIMPANIN_APP_GROUP = group.com.inez.Simpanin.dev;',
              'SIMPANIN_APP_GROUP = group.com.inez.Simpanin;'), True),
    ("Debug with Release's Keychain group", PROJECT,
     in_block('Debug', 'SIMPANIN_KEYCHAIN_GROUP = simpanin.vault.dev;', 'SIMPANIN_KEYCHAIN_GROUP = simpanin.vault;'),
     True),
    ('Debug without a Keychain group', PROJECT,
     in_block('Debug', '\n\t\t\t\tSIMPANIN_KEYCHAIN_GROUP = simpanin.vault.dev;', ''), True),
    ('a group named in Info.plist', INFO, replace(GROUP, '<string>group.com.inez.Simpanin</string>'), True),
    ('a group named in the entitlements', ENTITLEMENTS,
     replace(KEYCHAIN, '<string>$(AppIdentifierPrefix)simpanin.vault</string>'), True),
    ('a group named beside the variable', ENTITLEMENTS,
     replace(GROUP, GROUP + '<string>group.com.inez.Simpanin</string>'), True),
    ('Info.plist missing', None, remove(INFO), True),
]


def run(case):
    name, path, change, must_refuse = case
    with tempfile.TemporaryDirectory() as folder:
        for copied in (PROJECT, INFO, ENTITLEMENTS):
            os.makedirs(os.path.join(folder, os.path.dirname(copied)), exist_ok=True)
            shutil.copy(os.path.join(ROOT, copied), os.path.join(folder, copied))
        if path:
            target = os.path.join(folder, path)
            text = open(target, encoding='utf-8').read()
            open(target, 'w', encoding='utf-8').write(change(text))
        elif change:
            change(folder)
        here = os.getcwd()
        os.chdir(folder)
        try:
            problems = checks.release_identity_problems(True)
        finally:
            os.chdir(here)
    if bool(problems) != must_refuse:
        what = 'passed, but must be refused' if must_refuse else f'was refused: {problems}'
        return f'{name}: {what}'
    return None


def main():
    failures = [failure for failure in map(run, CASES) if failure]
    for failure in failures:
        print(f'test-commit-checks: {failure}', file=sys.stderr)
    if failures:
        return 1
    print(f'test-commit-checks: {len(CASES)} cases passed')
    return 0


if __name__ == '__main__':
    sys.exit(main())
