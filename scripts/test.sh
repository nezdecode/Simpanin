#!/bin/bash
# Runs the app's tests on the iOS 27 "iPhone 17" simulator and fails unless they ran and passed.
#   scripts/test.sh                              every test, unit and UI
#   scripts/test.sh --only SimpaninTests         one target, or Target/Class; repeat --only for several
#   scripts/test.sh --skip SimpaninTests         everything but a target or Target/Class; repeatable, and
#                                                applied after --only
# SIMPANIN_SIMULATOR names another simulator by id. SIMPANIN_IDLE_TIMEOUT (seconds, default 300) stops a
# run that prints nothing for that long: xcodebuild has hung after the build with no output. While Swift
# Testing's summary is the last thing out, the limit is 60 seconds, since xcodebuild often hangs there
# after a failing run.
# Its verdict comes from the result bundle, never from xcodebuild's exit status, and zero tests fail it:
# a filter naming one Swift Testing function matches nothing and would otherwise report success.
# A run it stops before any test failed runs once more on a freshly booted simulator; one stopped again, or
# after a failure, fails, whatever xcodebuild left in the bundle. A UI test gets 180 seconds, and no second
# try, and the run stops after three time out; any other test that fails gets one more. The summary names
# the tests that timed out and those that passed only on their retry.
set -euo pipefail
cd "$(dirname "$0")/.."

# Anything it doesn't know stops it: a filter it skipped once ran less than the command asked for.
filters=()
while [ $# -gt 0 ]; do
  case "$1" in
    --only | --skip)
      [ -n "${2:-}" ] && [ "${2#-}" = "$2" ] || { echo "test.sh: $1 needs a target or Target/Class" >&2; exit 2; }
      if [ "$1" = --only ]; then filters+=(-only-testing:"$2"); else filters+=(-skip-testing:"$2"); fi
      shift 2
      ;;
    *)
      echo "test.sh: unknown argument '$1'; use --only or --skip <Target or Target/Class>, as often as needed" >&2
      exit 2
      ;;
  esac
done

simulator="${SIMPANIN_SIMULATOR:-$(xcrun simctl list devices available -j | python3 -B -c '
import json, sys
for runtime, devices in json.load(sys.stdin)["devices"].items():
    if runtime.endswith("iOS-27-0"):
        for device in devices:
            if device["name"] == "iPhone 17":
                print(device["udid"])
                raise SystemExit
')}"
if [ -z "$simulator" ]; then
  echo "test.sh: no iOS 27 \"iPhone 17\" simulator; set SIMPANIN_SIMULATOR to a simulator id" >&2
  exit 1
fi
xcrun simctl bootstatus "$simulator" -b > /dev/null

idle_limit="${SIMPANIN_IDLE_TIMEOUT:-300}"
# Only while Swift Testing's summary is the last thing out: a run with UI tests goes on to them, and those
# get the full limit.
summary_idle_limit=60
timeout_limit=3
# Stops xcodebuild and its direct children (the build service, compilers) on any exit, Ctrl-C included.
# The test runner inside the simulator is launchd_sim's, not xcodebuild's; it ends with the run.
stop() {
  [ -n "${pid:-}" ] || return 0
  pkill -P "$pid" 2> /dev/null || true
  kill "$pid" 2> /dev/null || true
}
trap stop EXIT INT TERM

# Runs xcodebuild once with its log and result bundle in the folder it's given, stops it if it goes quiet,
# and prints the summary. Sets run, log, bundle and stopped for the verdict.
run_tests() {
  run="$1"
  mkdir -p "$run"
  log="$run/xcodebuild.log"
  bundle="$run/Tests.xcresult"
  echo "test.sh: simulator $simulator; log and results in $run"
  : > "$log"  # exists before the loop reads its time

  # Parallel testing clones the simulator. A clone once never finished booting, and with two clones UI
  # tests stalled for minutes in all three trials. CI splits the classes instead.
  # A test still running after 180 s fails with its name, the runner restarts and the run goes on; the
  # longest test takes about 30 s. The idle limit stays above it, so a stuck test is named rather than the
  # whole run stopped. A timed-out test isn't run again; any other test that fails is, and the summary
  # names it if it passes then.
  # Not -test-repetition-relaunch-enabled: with it, xcodebuild reran the whole class and then hung.
  xcodebuild test -project Simpanin.xcodeproj -scheme Simpanin \
    -destination "platform=iOS Simulator,id=$simulator" -destination-timeout 120 \
    -parallel-testing-enabled NO -derivedDataPath build/DerivedData-test \
    -test-timeouts-enabled YES -default-test-execution-time-allowance 180 \
    -retry-tests-on-failure -test-iterations 2 \
    -resultBundlePath "$bundle" "${filters[@]+"${filters[@]}"}" > "$log" 2>&1 &
  pid=$!
  stopped=""
  while kill -0 "$pid" 2> /dev/null; do
    if grep -qsE '\*\* TEST (SUCCEEDED|FAILED) \*\*' "$log"; then
      sleep 10  # time to finish writing the result bundle
      break
    fi
    # One stuck test is a test's problem; three mean the app hangs everywhere, say at launch. Each would
    # take 3 minutes, so CI would cancel the job before the summary named any.
    if [ "$(grep -c 'exceeded execution time allowance' "$log" || true)" -ge "$timeout_limit" ]; then
      echo "test.sh: $timeout_limit tests ran out of time, so the rest likely would too; stopping xcodebuild" >&2
      stopped=yes
      break
    fi
    idle=$(( $(date +%s) - $(stat -f %m "$log") ))
    if [ "$idle" -gt "$summary_idle_limit" ] && python3 -B scripts/xcodebuild-log.py after-summary "$log"; then
      echo "test.sh: no output for ${summary_idle_limit}s after Swift Testing's summary; stopping xcodebuild" >&2
      stopped=yes
      break
    fi
    if [ "$idle" -gt "$idle_limit" ]; then
      echo "test.sh: no output for ${idle_limit}s; stopping xcodebuild" >&2
      stopped=yes
      break
    fi
    sleep 5
  done
  stop
  wait "$pid" 2> /dev/null || true
  pid=""  # so the trap can't kill a process that took its number

  # Only names and counts: CI's log is public, and the script keeps out whatever can hold field values.
  python3 -B scripts/xcodebuild-log.py summary "$log"
}

run_tests "build/test-$(date +%Y%m%d-%H%M%S)"
# A run stopped before any test had failed hung in xcodebuild, the runner or the simulator, or in a Swift
# Testing unit test: the time allowance covers XCTest, and every XCTest here is a UI test. It runs once more
# on a freshly booted simulator.
if [ -n "$stopped" ] && what=$(python3 -B scripts/xcodebuild-log.py stopped "$log"); then
  # On GitHub a warning, so a job that passes on the retry still shows the hang on the pull request.
  [ "${GITHUB_ACTIONS:-}" = true ] && warning="::warning::" || warning=""
  echo "${warning}test.sh: $what; no test had failed, so running once more on a freshly booted simulator"
  xcrun simctl shutdown "$simulator" 2> /dev/null || true  # it may have shut down already
  xcrun simctl bootstatus "$simulator" -b > /dev/null
  run_tests "$run-retry"
fi
# A stopped xcodebuild may still have written a bundle, without the tests it never ran.
if [ -n "$stopped" ]; then
  echo "test.sh: $(python3 -B scripts/xcodebuild-log.py stopped "$log" || true)" >&2
  echo "test.sh: FAILED, xcodebuild was stopped; see $log" >&2
  exit 1
fi
if [ ! -f "$bundle/Info.plist" ] \
  || ! summary=$(xcrun xcresulttool get test-results summary --path "$bundle" 2> "$run/xcresulttool.err"); then
  echo "test.sh: FAILED, the result bundle is incomplete or unreadable; see $log and $run/xcresulttool.err" >&2
  exit 1
fi
echo "$summary" | python3 -B -c '
import json, sys
try:
    s = json.load(sys.stdin)
except json.JSONDecodeError:
    sys.exit("test.sh: FAILED, xcresulttool gave no summary")
total, failed = s.get("totalTestCount", 0), s.get("failedTests", 0)
passed, skipped = s.get("passedTests", 0), s.get("skippedTests", 0)
print(f"test.sh: {total} tests: {passed} passed, {failed} failed, {skipped} skipped")
if total == 0:
    sys.exit("test.sh: FAILED, no test ran: check the --only and --skip filters")
if failed or s.get("result") != "Passed":
    sys.exit("test.sh: FAILED")
print("test.sh: PASSED")
'
