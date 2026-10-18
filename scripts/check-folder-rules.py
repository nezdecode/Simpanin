#!/usr/bin/env python3
# Checks the app's folder rules (CODING.md section 1) on the app's files in git, the staged ones
# included. Exits 1 and lists every use that crosses them. Run by scripts/hooks/pre-commit; run it by
# hand with:
#   python3 scripts/check-folder-rules.py
#
# A layer may use only the layers listed for it. Features use each other only through the entry
# points below, and App uses features only through them too. Debug may reach anything, and anything
# may reach it.
#
# It matches the names of types declared at the top level of a file, in code (comments and string
# literals are left out). It doesn't see members added in extensions of system types, such as
# Calendar.gregorianUTC from Documents/, or global functions; review catches those.

import os
import re
import subprocess
import sys

MAY_USE = {
    'App': {'Platform', 'Documents', 'DesignSystem', 'Debug'},
    'Features': {'Platform', 'Documents', 'DesignSystem', 'Debug'},
    'DesignSystem': set(),  # no domain: no Platform, Documents or feature types
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
    if len(parts) < 2 or parts[0] not in MAY_USE and parts[0] != 'Debug':
        return None
    if parts[0] == 'Features':
        return 'Features/' + parts[1] if len(parts) > 2 else None
    return parts[0]


def code(text):
    """The text without comments and string literals, so neither counts as a use."""
    text = re.sub(r'"""(?:.|\n)*?"""', '""', text)
    text = re.sub(r'"(?:\\.|[^"\\\n])*"', '""', text)
    text = re.sub(r'/\*.*?\*/', '', text, flags=re.S)
    return re.sub(r'//[^\n]*', '', text)


def main():
    os.chdir(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    listed = subprocess.run(['git', 'ls-files', '--cached', '--', 'Simpanin/*.swift'],
                            capture_output=True, text=True, check=True).stdout.split()
    files = sorted(path for path in listed if os.path.exists(path))
    if not files:
        print('check-folder-rules: found no Swift files under Simpanin/', file=sys.stderr)
        return 1
    problems = [f'{path}: not in a folder the rules know (CODING.md section 1)'
                for path in files if layer(path) is None]
    files = [path for path in files if layer(path) is not None]
    raw = {path: open(path, encoding='utf-8').read() for path in files}
    sources = {path: code(text) for path, text in raw.items()}
    # Column 0 only: a nested type isn't a layer's own, and Debug's types sit inside #if DEBUG.
    home = {}
    for path, text in raw.items():
        for match in DECLARATION.finditer(text):
            home.setdefault(match.group(1), path)
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
