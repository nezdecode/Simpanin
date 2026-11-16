#!/usr/bin/env python3
# Reads the xcodebuild log that scripts/test.sh writes:
#   python3 scripts/xcodebuild-log.py summary <log>   the lines test.sh prints after a run
#   python3 scripts/xcodebuild-log.py stopped <log>   what was running when test.sh stopped the run;
#                                                     exits 1 when a test had failed, 0 otherwise
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
FAILED = re.compile(r"✘ Test .+ failed after|Test [Cc]ase '[^']+' failed")

# The system's output can share a line with these, so they're found anywhere in it.
XCTEST_START = re.compile(r"Test Case '-\[(?:\w+\.)?(\w+) (\w+)\]' started\.$")
XCTEST_END = re.compile(r"Test Case '-\[(?:\w+\.)?(\w+) (\w+)\]' (passed|failed|skipped)")
SWIFT_START = re.compile(r"◇ Test (.+) started\.$")
# A parameterized test ends "Test name(_:) with 3 test cases passed after …".
SWIFT_END = re.compile(r"[✔✘➜] Test (.+?)(?: with [0-9]+ test cases?)? (passed after|failed after|skipped)")
# A parameterized case's line holds its arguments' values; "Test run" is the whole run, not a test.
NOT_A_NAME = re.compile(r"^(case passing |run$|run with )")
# Build steps and xcodebuild's own messages start at the margin with a word, like "CompileSwift".
STEP = re.compile(r"^([A-Za-z]+)\b")
SHOWN_RUNNING = 5


def summary(lines):
    """The lines worth printing after a run, each once, in byte order."""
    return sorted({line for line in lines if SUMMARY.search(line) and not NEVER.search(line)})


def stopped(lines):
    """What was running when the run stopped, and whether a test had failed by then."""
    running, last_finished, started, step = {}, None, False, None
    for line in lines:
        if match := XCTEST_START.search(line):
            running[f'{match[1]}.{match[2]}'] = True
        elif match := XCTEST_END.search(line):
            running.pop(f'{match[1]}.{match[2]}', None)
            last_finished = f'{match[1]}.{match[2]}'
        elif (match := SWIFT_START.search(line)) and not NOT_A_NAME.match(match[1]):
            running[match[1]] = True
        elif (match := SWIFT_END.search(line)) and not NOT_A_NAME.match(match[1]):
            running.pop(match[1], None)
            last_finished = match[1]
        elif match := STEP.match(line):
            step = match[1]
            continue
        else:
            continue
        started = True
    if running:
        names = list(running)
        more = f' and {len(names) - SHOWN_RUNNING} more' if len(names) > SHOWN_RUNNING else ''
        message = f'stopped during {", ".join(names[:SHOWN_RUNNING])}{more}, still running'
    elif started:
        message = f'stopped after {last_finished}, before the next test'
    else:
        message = f'no test had started; last step: {step or "none"}'
    return message, any(FAILED.search(line) for line in lines)


def read(path):
    with open(path, encoding='utf-8', errors='surrogateescape', newline='') as log:
        return log.read().split('\n')


def main(argv):
    if len(argv) != 3 or argv[1] not in ('summary', 'stopped'):
        print('usage: xcodebuild-log.py summary|stopped <log>', file=sys.stderr)
        return 2
    sys.stdout.reconfigure(errors='surrogateescape')
    lines = read(argv[2])
    if argv[1] == 'stopped':
        message, failed = stopped(lines)
        print(message)
        return 1 if failed else 0
    for line in summary(lines):
        print(line)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
