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

# A Swift Testing name: a function, or a display name in quotes. Matching only that keeps an issue's text,
# which can contain "failed after" too, out of the log.
SWIFT_NAME = r'([A-Za-z_]\w*\([\w:]*\)|"[^"]*")'
# "Test Case" is XCTest's serial form, "Test case … failed on 'Clone 1 …'" its parallel one. Only a
# diagnostic's own shapes of "error:" count: an issue's text ("Caught error: …") or a crash's message can
# hold a value.
SUMMARY = re.compile(
    r"Test run with [0-9]+ tests?|✘ Test " + SWIFT_NAME + r"(?: with [0-9]+ test cases?)? failed after"
    r"|Test [Cc]ase '[^']+' failed|Executed [0-9]+ tests?|\*\* TEST"
    r"|^(?:\S+:[0-9]+(?::[0-9]+)?: |xcodebuild: |macro expansion [#@]\w+:[0-9]+:[0-9]+: )?error: "
)
NEVER = re.compile(r"error: -\[|^\s+(t = |\u21aa\ufe0e)")
# The app's log lines start with a timestamp, and output can push one into the middle of another line, so a
# line is cut where one starts.
TIMESTAMP = re.compile(r"[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:")

# The system's output can share a line with these, so they're found anywhere in it, but a name must look
# like one: an issue's text can contain "passed after" too. A retry starts "started (Iteration 2 of 2)."
# in XCTest and "started (repetition 2)." in Swift Testing, where the failure before it shows only as
# "recorded an issue". A test past its time allowance ends "exceeded execution time allowance of 3
# minutes", and the runner restarts.
XCTEST_START = re.compile(r"Test Case '-\[(?:\w+\.)?(\w+) (\w+)\]' started(?: \(Iteration ([0-9]+) of [0-9]+\))?\.$")
XCTEST_END = re.compile(
    r"Test Case '-\[(?:\w+\.)?(\w+) (\w+)\]' (passed|failed|skipped|exceeded execution time allowance)"
)
SWIFT_START = re.compile(r"◇ Test " + SWIFT_NAME + r" started(?: \(repetition ([0-9]+)\))?\.$")
# A parameterized test ends "Test name(_:) with 3 test cases passed after 0.1 seconds.".
SWIFT_END = re.compile(
    r"[✔✘➜] Test " + SWIFT_NAME + r"(?: with [0-9]+ test cases?)? (passed after|failed after|skipped)"
)
# The first sign a Swift Testing test failed: its result comes only when it ends, and it may hang first.
SWIFT_ISSUE = re.compile(r"✘ Test " + SWIFT_NAME + r" recorded an issue")
OUTCOME = {
    'passed': 'passed', 'passed after': 'passed', 'failed': 'failed', 'failed after': 'failed',
    'skipped': 'skipped', 'exceeded execution time allowance': 'timed out',
}
FAILURES = ('failed', 'timed out')
# A test whose last event is an issue, or a retry's start, has failed and hasn't passed since.
STANDS = FAILURES + ('issue', 'retry')
# Build steps start at the margin with their name. Other words there can come from anywhere, even the app,
# so only these are named.
STEP = re.compile(r"^([A-Za-z]+)\b")
STEPS = {
    'AppIntentsSSUTraining', 'Build', 'ClangStatCache', 'CodeSign', 'Command', 'CompileAssetCatalogVariant',
    'ComputePackagePrebuildTargetDependencyGraph', 'ComputeTargetDependencyGraph',
    'ConstructStubExecutorLinkFileList', 'Copy', 'CopyPlistFile', 'CopySwiftLibs', 'CreateBuildDescription',
    'CreateBuildOperation', 'CreateBuildRequest', 'ExecuteExternalTool', 'ExtractAppIntentsMetadata',
    'GatherProvisioningInputs', 'GenerateAssetSymbols', 'Ld', 'LinkAssetCatalog', 'Prepare',
    'ProcessInfoPlistFile', 'PruneExplicitPrecompiledModules', 'ReadFileContents', 'Resolve', 'Resolved',
    'Retrying', 'SendProjectDescription', 'SwiftCompile', 'SwiftDriver', 'SwiftDriverJobDiscovery',
    'SwiftEmitModule', 'SwiftExplicitDependencyCompileModuleFromInterface', 'SwiftExplicitDependencyGeneratePcm',
    'SwiftMergeGeneratedHeaders', 'Test', 'Testing', 'Validate', 'WriteAuxiliaryFile', 'Writing',
}
SHOWN_RUNNING = 5
SWIFT_SUMMARY = re.compile(r"Test run with [0-9]+ tests?")
XCTEST_SUITE_START = re.compile(r"Test Suite '[^']+' started")
# A class's suite ends with its time on the next line. "Selected tests" and "SimpaninUITests.xctest" don't
# match, and a class split by a runner restart has a part per launch.
CLASS_END = re.compile(r"^Test Suite '(\w+)' (passed|failed) at ")
CLASS_TIME = re.compile(r"Executed ([0-9]+) tests?, with .* in ([0-9.]+) \(")


def test_event(line):
    """A test's name and what happened to it on this line ("started", "issue", "retry", "passed" …), if
    any. A parameterized case's line holds its arguments' values, and its name never matches."""
    if match := XCTEST_START.search(line):
        return f'{match[1]}.{match[2]}', 'retry' if int(match[3] or 1) > 1 else 'started'
    if match := XCTEST_END.search(line):
        return f'{match[1]}.{match[2]}', OUTCOME[match[3]]
    if match := SWIFT_START.search(line):
        return match[1], 'retry' if int(match[2] or 1) > 1 else 'started'
    if match := SWIFT_END.search(line):
        return match[1], OUTCOME[match[2]]
    if match := SWIFT_ISSUE.search(line):
        return match[1], 'issue'
    return None, None


def scan(lines):
    """The tests still running, each test's results in order, the last to finish and the last build step."""
    # shortcut: Swift Testing's lines name a test without its suite, so two suites' tests of the same name
    # would share results (a false "flaky"); none do on 16 Nov 2026. Key them by suite if two ever do.
    running, results, last_finished, step = {}, {}, None, None
    for line in lines:
        name, outcome = test_event(line)
        if name is None:
            if match := STEP.match(line):
                step = match[1] if match[1] in STEPS else 'other'
        elif outcome == 'started':
            running[name] = True
        elif outcome in ('issue', 'retry'):
            running[name] = True
            results.setdefault(name, []).append(outcome)
        else:
            running.pop(name, None)
            results.setdefault(name, []).append(outcome)
            last_finished = name
    return running, results, last_finished, step


def class_times(lines):
    """Each XCTest class's tests and seconds, slowest first, for balancing CI's jobs."""
    times, ended = {}, None
    for line in lines:
        if match := CLASS_END.search(line):
            ended = match[1]
        elif ended and (match := CLASS_TIME.search(line)):
            tests, seconds = times.get(ended, (0, 0.0))
            times[ended] = (tests + int(match[1]), seconds + float(match[2]))
            ended = None
    return sorted(times.items(), key=lambda item: -item[1][1])


def summary(lines, on_github=False):
    """The lines worth printing after a run: names and counts each once in byte order, each class's time,
    then the tests that timed out and those that passed only on their retry."""
    cut = (TIMESTAMP.split(line, maxsplit=1)[0] for line in lines)
    printed = sorted({line for line in cut if SUMMARY.search(line) and not NEVER.search(line)})
    printed += [
        f'class time: {name}, {tests} tests, {seconds / 60:.1f} min' for name, (tests, seconds) in class_times(lines)
    ]
    _, results, _, _ = scan(lines)
    printed += [f'{name}: timed out' for name, outcomes in results.items() if 'timed out' in outcomes]
    # On CI a warning shows on the pull request's checks, so a passing run can't hide a flaky test.
    flag = '::warning::' if on_github else ''
    printed += [
        f'{flag}flaky: {name} failed, then passed on its retry'
        for name, outcomes in results.items()
        if outcomes[-1] == 'passed' and any(outcome in STANDS for outcome in outcomes)
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
    return message, any(outcomes[-1] in STANDS for outcomes in results.values())


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
