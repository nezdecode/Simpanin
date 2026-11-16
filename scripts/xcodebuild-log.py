#!/usr/bin/env python3
# Reads the xcodebuild log that scripts/test.sh writes:
#   python3 scripts/xcodebuild-log.py summary <log>   the lines test.sh prints after a run
#   python3 scripts/xcodebuild-log.py stopped <log>   what was running when test.sh stopped the run;
#                                                     exits 1 when a test's last result was a failure
#   python3 scripts/xcodebuild-log.py after-summary <log>   exits 0 when Swift Testing's summary is out
#                                                     and no XCTest suite has started since
# CI's log is public, so all this prints is test names, counts and xcodebuild's own words. A failure's
# details, an XCTest "error: -[…]" line, its indented activity lines (a query can name a label) and the
# app's log lines (they start with a timestamp) can hold field values. Tested by
# scripts/test-xcodebuild-log.py.

import os
import re
import sys

# "Test Case" is XCTest's serial form, "Test case … failed on 'Clone 1 …'" its parallel one.
SUMMARY = re.compile(
    r"Test run with [0-9]+ tests|✘ Test .+ failed after|Test [Cc]ase '[^']+' failed|Executed [0-9]+ tests"
    r"|\*\* TEST|error:"
)
NEVER = re.compile(r"error: -\[|^\s+(t = |\u21aa\ufe0e)|^[0-9]{4}-[0-9]{2}-[0-9]{2} ")

# The system's output can share a line with these, so they're found anywhere in it. With retries on, a
# start reads "started (Iteration 1 of 2)."; a test past its time allowance ends "exceeded execution time
# allowance of 3 minutes", and the runner restarts.
XCTEST_START = re.compile(r"Test Case '-\[(?:\w+\.)?(\w+) (\w+)\]' started(?: \(Iteration [0-9]+ of [0-9]+\))?\.$")
XCTEST_END = re.compile(
    r"Test Case '-\[(?:\w+\.)?(\w+) (\w+)\]' (passed|failed|skipped|exceeded execution time allowance)"
)
SWIFT_START = re.compile(r"◇ Test (.+) started\.$")
# A parameterized test ends "Test name(_:) with 3 test cases passed after …".
SWIFT_END = re.compile(r"[✔✘➜] Test (.+?)(?: with [0-9]+ test cases?)? (passed after|failed after|skipped)")
OUTCOME = {
    'passed': 'passed', 'passed after': 'passed', 'failed': 'failed', 'failed after': 'failed',
    'skipped': 'skipped', 'exceeded execution time allowance': 'timed out',
}
FAILURES = ('failed', 'timed out')
# A parameterized case's line holds its arguments' values; "Test run" is the whole run, not a test.
NOT_A_NAME = re.compile(r"^(case passing |run$|run with )")
# Build steps and xcodebuild's own messages start at the margin with a word, like "CompileSwift".
STEP = re.compile(r"^([A-Za-z]+)\b")
SHOWN_RUNNING = 5
SWIFT_SUMMARY = re.compile(r"Test run with [0-9]+ tests")
XCTEST_SUITE_START = re.compile(r"Test Suite '[^']+' started")


def test_event(line):
    """A test's name and what happened to it on this line ("started", "passed", "timed out" …), if any."""
    if match := XCTEST_START.search(line):
        return f'{match[1]}.{match[2]}', 'started'
    if match := XCTEST_END.search(line):
        return f'{match[1]}.{match[2]}', OUTCOME[match[3]]
    if (match := SWIFT_START.search(line)) and not NOT_A_NAME.match(match[1]):
        return match[1], 'started'
    if (match := SWIFT_END.search(line)) and not NOT_A_NAME.match(match[1]):
        return match[1], OUTCOME[match[2]]
    return None, None


def scan(lines):
    """The tests still running, each test's results in order, the last to finish and the last build step."""
    running, results, last_finished, step = {}, {}, None, None
    for line in lines:
        name, outcome = test_event(line)
        if name is None:
            if match := STEP.match(line):
                step = match[1]
        elif outcome == 'started':
            running[name] = True
        else:
            running.pop(name, None)
            results.setdefault(name, []).append(outcome)
            last_finished = name
    return running, results, last_finished, step


def summary(lines, on_github=False):
    """The lines worth printing after a run: names and counts each once in byte order, then the tests that
    timed out and those that passed only on their retry."""
    printed = sorted({line for line in lines if SUMMARY.search(line) and not NEVER.search(line)})
    _, results, _, _ = scan(lines)
    printed += [f'{name}: timed out' for name, outcomes in results.items() if 'timed out' in outcomes]
    # On CI a warning shows on the pull request's checks, so a passing run can't hide a flaky test.
    flag = '::warning::' if on_github else ''
    printed += [
        f'{flag}flaky: {name} failed, then passed on its retry'
        for name, outcomes in results.items()
        if outcomes[-1] == 'passed' and any(outcome in FAILURES for outcome in outcomes)
    ]
    return printed


def stopped(lines):
    """What was running when the run stopped, and whether a test's last result by then was a failure."""
    running, results, last_finished, step = scan(lines)
    if running:
        names = list(running)
        more = f' and {len(names) - SHOWN_RUNNING} more' if len(names) > SHOWN_RUNNING else ''
        message = f'stopped during {", ".join(names[:SHOWN_RUNNING])}{more}, still running'
    elif results:
        message = f'stopped after {last_finished}, before the next test'
    else:
        message = f'no test had started; last step: {step or "none"}'
    return message, any(outcomes[-1] in FAILURES for outcomes in results.values())


def after_summary(lines):
    """Whether Swift Testing's summary is out and no XCTest suite has started since."""
    after = False
    for line in lines:
        if SWIFT_SUMMARY.search(line):
            after = True
        elif XCTEST_SUITE_START.search(line):
            after = False
    return after


def read(path):
    with open(path, encoding='utf-8', errors='surrogateescape', newline='') as log:
        return log.read().split('\n')


def main(argv):
    if len(argv) != 3 or argv[1] not in ('summary', 'stopped', 'after-summary'):
        print('usage: xcodebuild-log.py summary|stopped|after-summary <log>', file=sys.stderr)
        return 2
    sys.stdout.reconfigure(errors='surrogateescape')
    lines = read(argv[2])
    if argv[1] == 'after-summary':
        return 0 if after_summary(lines) else 1
    if argv[1] == 'stopped':
        message, failed = stopped(lines)
        print(message)
        return 1 if failed else 0
    for line in summary(lines, on_github=os.environ.get('GITHUB_ACTIONS') == 'true'):
        print(line)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
