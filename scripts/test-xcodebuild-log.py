#!/usr/bin/env python3
# Tests scripts/xcodebuild-log.py, which decides what of a test run reaches CI's public log. Every log
# here is made up, and every value in it is a stand-in for something a real log could hold. Run by
# scripts/ci-checks.sh; by hand with:
#   python3 scripts/test-xcodebuild-log.py

import importlib.util
import os
import sys

sys.dont_write_bytecode = True
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
spec = importlib.util.spec_from_file_location('xcodebuild_log', os.path.join(ROOT, 'scripts', 'xcodebuild-log.py'))
log = importlib.util.module_from_spec(spec)
spec.loader.exec_module(log)

# Text that must never be printed: what a failure, an argument or the app's log could carry.
SECRET = 'Budi Contoh'

RUN = f"""\
Resolve Package Graph
CompileSwift normal arm64 /work/Simpanin/Simpanin/App/AppSetup.swift
◇ Test run started.
◇ Test case passing 1 argument name → "{SECRET}" to namesAreKept(_:) started.
✘ Test namesAreKept(_:) recorded an issue at NameTests.swift:12:5: Expectation failed: "{SECRET}" == ""
✘ Test namesAreKept(_:) failed after 0.010 seconds with 1 issue.
✘ Test run with 3 tests in 1 suite failed after 0.020 seconds with 1 issue.
Test Suite 'Selected tests' started at 2026-11-16 16:33:21.691.
Test Case '-[SimpaninUITests.LibraryUITests testTheListShowsANewDocument]' started.
    t =     1.02s Tap "{SECRET}" StaticText
    ↪︎Find: Descendants matching type StaticText
/work/Simpanin/SimpaninUITests/LibraryUITests.swift:40: error: -[SimpaninUITests.LibraryUITests testTheListShowsANewDocument] : XCTAssertTrue failed: "{SECRET}"
2026-11-16 16:40:00.000 Simpanin[123:456] [ShareSheet] Failed for {SECRET} error: Error Domain=NSCocoaErrorDomain
Test Case '-[SimpaninUITests.LibraryUITests testTheListShowsANewDocument]' failed (12.345 seconds).
Test Case '-[SimpaninUITests.LibraryUITests testTheListShowsANewDocument]' failed (12.345 seconds).
Test case 'LibraryUITests.testTheListShowsANewDocument()' failed on 'Clone 1 of iPhone 17' (12.3 seconds)
	 Executed 2 tests, with 1 failure (0 unexpected) in 12.345 (12.350) seconds
/work/Simpanin/Simpanin/App/AppSetup.swift:10:5: error: cannot find 'vault' in scope
** TEST FAILED **
"""


def summary_keeps_names_and_counts():
    expected = [
        "\t Executed 2 tests, with 1 failure (0 unexpected) in 12.345 (12.350) seconds",
        "** TEST FAILED **",
        "/work/Simpanin/Simpanin/App/AppSetup.swift:10:5: error: cannot find 'vault' in scope",
        "Test Case '-[SimpaninUITests.LibraryUITests testTheListShowsANewDocument]' failed (12.345 seconds).",
        "Test case 'LibraryUITests.testTheListShowsANewDocument()' failed on 'Clone 1 of iPhone 17' (12.3 seconds)",
        "✘ Test namesAreKept(_:) failed after 0.010 seconds with 1 issue.",
        "✘ Test run with 3 tests in 1 suite failed after 0.020 seconds with 1 issue.",
    ]
    got = log.summary(RUN.split('\n'))
    return None if got == expected else f'got {got}'


def summary_never_prints_values():
    leaked = [line for line in log.summary(RUN.split('\n')) if SECRET in line]
    return None if not leaked else f'leaked {leaked}'


CASES = [summary_keeps_names_and_counts, summary_never_prints_values]


def main():
    failures = [f'{case.__name__}: {problem}' for case in CASES if (problem := case())]
    for failure in failures:
        print(f'test-xcodebuild-log: {failure}', file=sys.stderr)
    if failures:
        return 1
    print(f'test-xcodebuild-log: {len(CASES)} cases passed')
    return 0


if __name__ == '__main__':
    sys.exit(main())
