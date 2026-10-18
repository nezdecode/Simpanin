#!/usr/bin/env python3
# Checks the app's folder rules (CODING.md section 1) on the working tree. Exits 1 and lists every
# use that crosses them. Run by scripts/hooks/pre-commit; run it by hand with:
#   python3 scripts/check-folder-rules.py
#
# A layer may use the layers listed for it. Features use each other only through the entry points
# below, and App uses features only through them too. Debug may reach anything, and anything may
# reach it. Types are matched by name, in code only (comments are left out).

import glob
import re
import sys

MAY_USE = {
    'App': {'Platform', 'Documents', 'DesignSystem', 'Debug'},
    'Features': {'Platform', 'Documents', 'DesignSystem', 'Debug'},
    'DesignSystem': {'Platform'},  # no domain: no Documents, no features
    'Documents': {'Platform'},
    'Platform': set(),  # knows nothing about features
}

# Each feature's entry points: a type name, or a pattern when only one member of it is allowed.
ENTRY_POINTS = {
    'LibraryView': None,
    'RecentlyDeletedView': None,
    'LibraryModel': None,
    'ScanFlowView': None,
    'DocumentCamera': r'\bDocumentCamera\.isSupported\b',
    'DocumentCameraCache': r'\bDocumentCameraCache\.clear\(\)',
    'SettingsView': None,
    'LockCoverView': None,
}

DECLARATION = re.compile(
    r'^(?:@\w+(?:\([^)]*\))?\s+)*(?:(?:public|private|fileprivate|internal|nonisolated|final)\s+)*'
    r'(?:struct|class|enum|actor|protocol)\s+([A-Z]\w*)',
    re.M)


def layer(path):
    parts = path.split('/')[1:]
    return 'Features/' + parts[1] if parts[0] == 'Features' else parts[0]


def code(text):
    text = re.sub(r'/\*.*?\*/', '', text, flags=re.S)
    return re.sub(r'//[^\n]*', '', text)


def main():
    files = sorted(glob.glob('Simpanin/**/*.swift', recursive=True))
    sources = {path: code(open(path, encoding='utf-8').read()) for path in files}
    # Column 0 only: a nested type isn't a layer's own, and Debug's types sit inside #if DEBUG.
    home = {}
    for path in files:
        for match in DECLARATION.finditer(open(path, encoding='utf-8').read()):
            home.setdefault(match.group(1), path)
    problems = []
    for name, declared_in in sorted(home.items()):
        owner = layer(declared_in)
        if owner == 'Debug':
            continue
        for path, text in sources.items():
            user = layer(path)
            if user in (owner, 'Debug'):
                continue
            uses = len(re.findall(r'\b%s\b' % name, text))
            if not uses:
                continue
            user_top, owner_top = user.split('/')[0], owner.split('/')[0]
            if owner_top in MAY_USE[user_top] and owner_top != 'Features':
                continue
            if owner_top == 'Features' and user_top in ('App', 'Features') and name in ENTRY_POINTS:
                pattern = ENTRY_POINTS[name]
                if pattern is None or len(re.findall(pattern, text)) == uses:
                    continue
            problems.append(f'{path}: uses {name} from {owner}')
    if problems:
        print('Folder rules (CODING.md section 1) broken:', file=sys.stderr)
        for problem in problems:
            print('  ' + problem, file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
