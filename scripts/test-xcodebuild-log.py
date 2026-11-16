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
SwiftCompile normal arm64 /work/Simpanin/Simpanin/App/AppSetup.swift
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
	 Executed 1 test, with 1 failure (0 unexpected) in 12.345 (12.351) seconds
/work/Simpanin/Simpanin/App/AppSetup.swift:10:5: error: cannot find 'vault' in scope
** TEST FAILED **
"""


def summary_keeps_names_and_counts():
    expected = [
        "\t Executed 1 test, with 1 failure (0 unexpected) in 12.345 (12.351) seconds",
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


def expect_stopped(text, message, failed):
    got = log.stopped(text.split('\n'))
    return None if got == (message, failed) else f'got {got}'


def stopped_names_the_ui_test_still_running():
    return expect_stopped(
        """\
Test Case '-[SimpaninUITests.LibraryUITests testOne]' started.
Test Case '-[SimpaninUITests.LibraryUITests testOne]' passed (3.000 seconds).
Test Case '-[SimpaninUITests.LibraryUITests testTwo]' started.
    t =     1.02s Wait for app to idle""",
        'stopped during LibraryUITests.testTwo, still running',
        False,
    )


def stopped_names_unit_tests_still_running_and_never_arguments():
    return expect_stopped(
        f"""\
◇ Test run started.
◇ Test first() started.
◇ Test second(_:) started.
◇ Test case passing 1 argument name → "{SECRET}" to second(_:) started.
some system outputs✔ Test first() passed after 0.001 seconds.""",
        'stopped during second(_:), still running',
        False,
    )


def stopped_between_tests_names_the_last_one_finished():
    return expect_stopped(
        """\
◇ Test aClock(_:) started.
✔ Test aClock(_:) with 3 test cases passed after 0.001 seconds.
✔ Test run with 1 test in 1 suite passed after 0.002 seconds.""",
        'stopped after aClock(_:), before the next test',
        False,
    )


def stopped_before_any_test_names_the_last_step():
    return expect_stopped(
        f"""\
Resolve Package Graph
SwiftCompile normal arm64 /work/Simpanin/Simpanin/App/AppSetup.swift
    cd /work/Simpanin
2026-11-16 16:40:00.000 Simpanin[1:2] {SECRET}
◇ Test run started.
""",
        'no test had started; last step: SwiftCompile',
        False,
    )


def stopped_says_when_a_test_had_failed():
    return expect_stopped(
        """\
Test Case '-[SimpaninUITests.LibraryUITests testOne]' started.
Test Case '-[SimpaninUITests.LibraryUITests testOne]' failed (3.000 seconds).""",
        'stopped after LibraryUITests.testOne, before the next test',
        True,
    )


def stopped_shortens_a_long_list():
    starts = '\n'.join(f'◇ Test t{number}() started.' for number in range(7))
    return expect_stopped(starts, 'stopped during t0(), t1(), t2(), t3(), t4() and 2 more, still running', False)


def after_summary_only_while_nothing_followed():
    summary = "Test Suite 'All tests' started at 2026-11-16 16:33:08.473.\n✔ Test run with 2 tests in 1 suite passed after 0.1 seconds."
    ui = summary + "\nTest Suite 'Selected tests' started at 2026-11-16 16:33:21.691."
    one = '✘ Test run with 1 test in 1 suite failed after 0.014 seconds with 1 issue.'
    got = [log.after_summary(text.split('\n')) for text in ("◇ Test run started.", summary, ui, one)]
    return None if got == [False, True, False, True] else f'got {got}'


RETRIED = """\
Test Case '-[SimpaninUITests.SettingsUITests testFlaky]' started (Iteration 1 of 2).
Test Case '-[SimpaninUITests.SettingsUITests testFlaky]' failed (0.174 seconds).
Test Case '-[SimpaninUITests.SettingsUITests testFlaky]' started (Iteration 2 of 2).
Test Case '-[SimpaninUITests.SettingsUITests testFlaky]' passed (11.304 seconds).
Test Case '-[SimpaninUITests.SettingsUITests testStuck]' started (Iteration 1 of 2).
Test Case '-[SimpaninUITests.SettingsUITests testStuck]' exceeded execution time allowance of 3 minutes. The test may have hung.
Restarting after unexpected exit, crash, or test timeout; summary will include totals from previous launches.
** TEST FAILED **"""


def summary_names_timeouts_and_flaky_tests():
    got = log.summary(RETRIED.split('\n'))[-2:]
    expected = [
        'SettingsUITests.testStuck: timed out',
        'flaky: SettingsUITests.testFlaky failed, then passed on its retry',
    ]
    return None if got == expected else f'got {got}'


def summary_warns_of_flaky_tests_on_github():
    got = log.summary(RETRIED.split('\n'), on_github=True)[-1]
    return None if got.startswith('::warning::flaky: SettingsUITests.testFlaky') else f'got {got}'


def stopped_counts_a_timeout_as_a_failure_and_a_retried_pass_as_none():
    flaky_only = '\n'.join(RETRIED.split('\n')[:4])
    got = [log.stopped(RETRIED.split('\n')), log.stopped(flaky_only.split('\n'))]
    expected = [
        ('stopped after SettingsUITests.testStuck, before the next test', True),
        ('stopped after SettingsUITests.testFlaky, before the next test', False),
    ]
    return None if got == expected else f'got {got}'


def stopped_during_a_retry_after_a_failure_stands():
    retrying = '\n'.join(RETRIED.split('\n')[:3])
    return expect_stopped(retrying, 'stopped during SettingsUITests.testFlaky, still running', True)


def summary_gives_each_class_its_time():
    text = """\
Test Suite 'Selected tests' started at 2026-11-16 19:00:00.000.
Test Suite 'SettingsUITests' failed at 2026-11-16 19:03:00.000.
\t Executed 1 test, with 1 failure (0 unexpected) in 190.000 (190.010) seconds
Test Suite 'SimpaninUITests.xctest' failed at 2026-11-16 19:03:00.000.
\t Executed 1 test, with 1 failure (0 unexpected) in 190.000 (190.020) seconds
Test Suite 'SettingsUITests' passed at 2026-11-16 19:04:00.000.
\t Executed 1 test, with 0 failures (0 unexpected) in 20.000 (20.010) seconds
Test Suite 'LibraryUITests' passed at 2026-11-16 19:08:00.000.
\t Executed 4 tests, with 0 failures (0 unexpected) in 240.000 (240.010) seconds
Test Suite 'Selected tests' passed at 2026-11-16 19:08:00.000.
\t Executed 6 tests, with 1 failure (0 unexpected) in 450.000 (450.030) seconds"""
    got = [line for line in log.summary(text.split('\n')) if line.startswith('class time')]
    expected = ['class time: LibraryUITests, 4 tests, 4.0 min', 'class time: SettingsUITests, 2 tests, 3.5 min']
    return None if got == expected else f'got {got}'


def issue_text_is_never_a_name():
    text = f"""\
✔ Test first() passed after 0.001 seconds.
✘ Test first() recorded an issue at A.swift:3:5: Expectation failed: (status → "{SECRET} passed after") == ""
✘ Test second() recorded an issue at A.swift:9:5: Expectation failed: "{SECRET} failed after 1 skipped" == ""
✘ Test third() recorded an issue at A.swift:12:5: Caught error: "{SECRET}"
Swift/ContiguousArrayBuffer.swift:695: Fatal error: {SECRET}
Test case '-[T.A b]' failed on 'Clone 2' (1.0 secon2026-11-15 21:40:35.003 Simpanin[1:2] {SECRET}
{SECRET} was here"""
    lines = text.split('\n')
    printed = log.summary(lines) + [log.stopped(lines)[0], log.stopped(lines[-1:])[0]]
    if "Test case '-[T.A b]' failed on 'Clone 2' (1.0 secon" not in printed:
        return f'a failed test cut at a timestamp went missing: {printed}'
    # Even one word of it: a margin line's first word is all `stopped` could print.
    leaked = [line for line in printed if SECRET.split()[0] in line]
    return None if not leaked else f'leaked {leaked}'


CASES = [
    issue_text_is_never_a_name,
    summary_gives_each_class_its_time,
    summary_names_timeouts_and_flaky_tests,
    summary_warns_of_flaky_tests_on_github,
    stopped_counts_a_timeout_as_a_failure_and_a_retried_pass_as_none,
    stopped_during_a_retry_after_a_failure_stands,
    after_summary_only_while_nothing_followed,
    summary_keeps_names_and_counts,
    summary_never_prints_values,
    stopped_names_the_ui_test_still_running,
    stopped_names_unit_tests_still_running_and_never_arguments,
    stopped_between_tests_names_the_last_one_finished,
    stopped_before_any_test_names_the_last_step,
    stopped_says_when_a_test_had_failed,
    stopped_shortens_a_long_list,
]


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
