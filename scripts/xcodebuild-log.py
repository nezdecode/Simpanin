#!/usr/bin/env python3
# Reads the xcodebuild log that scripts/test.sh writes:
#   python3 scripts/xcodebuild-log.py summary <log>   the lines test.sh prints after a run
# CI's log is public, so all this prints is test names, counts and xcodebuild's own words. A failure's
# details, an XCTest "error: -[…]" line, its indented activity lines (a query can name a label) and the
# app's log lines (they start with a timestamp) can hold field values. Tested by
# scripts/test-xcodebuild-log.py.

import re
import sys

# "Test Case" is XCTest's serial form, "Test case … failed on 'Clone 1 …'" its parallel one.
SUMMARY = re.compile(
    r"Test run with [0-9]+ tests|✘ Test .+ failed after|Test [Cc]ase '[^']+' failed|Executed [0-9]+ tests"
    r"|\*\* TEST|error:"
)
NEVER = re.compile(r"error: -\[|^\s+(t = |↪︎)|^[0-9]{4}-[0-9]{2}-[0-9]{2} ")


def summary(lines):
    """The lines worth printing after a run, each once, in byte order."""
    return sorted({line for line in lines if SUMMARY.search(line) and not NEVER.search(line)})


def read(path):
    with open(path, encoding='utf-8', errors='surrogateescape', newline='') as log:
        return log.read().split('\n')


def main(argv):
    if len(argv) != 3 or argv[1] != 'summary':
        print('usage: xcodebuild-log.py summary <log>', file=sys.stderr)
        return 2
    sys.stdout.reconfigure(errors='surrogateescape')
    for line in summary(read(argv[2])):
        print(line)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
