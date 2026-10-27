#!/bin/bash
# Runs the app's tests on the iOS 27 "iPhone 17" simulator and fails unless they ran and passed.
#   scripts/test.sh                              every test, unit and UI
#   scripts/test.sh --only SimpaninTests         one target, or Target/Class
# SIMPANIN_SIMULATOR names another simulator by id. SIMPANIN_IDLE_TIMEOUT (seconds, default 300) stops a
# run that prints nothing for that long: xcodebuild has hung after the build with no output. After Swift
# Testing's summary the limit is 60 seconds, since xcodebuild often hangs there after a failing run.
# Its verdict comes from the result bundle, never from xcodebuild's exit status, and zero tests fail it:
# a filter naming one Swift Testing function matches nothing and would otherwise report success.
# A stopped run leaves an incomplete bundle, which always fails.
set -euo pipefail
cd "$(dirname "$0")/.."

only=()
if [ "${1:-}" = "--only" ]; then
  only=(-only-testing:"${2:?--only needs a target or Target/Class}")
fi

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

run="build/test-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$run"
log="$run/xcodebuild.log"
bundle="$run/Tests.xcresult"
echo "test.sh: simulator $simulator; log and results in $run"
: > "$log"  # exists before the loop reads its time

# Parallel testing clones the simulator, and a clone once never finished booting.
xcodebuild test -project Simpanin.xcodeproj -scheme Simpanin \
  -destination "platform=iOS Simulator,id=$simulator" -destination-timeout 120 \
  -parallel-testing-enabled NO -derivedDataPath build/DerivedData-test \
  -resultBundlePath "$bundle" "${only[@]+"${only[@]}"}" > "$log" 2>&1 &
pid=$!
# Stops xcodebuild and its direct children (the build service, compilers) on any exit, Ctrl-C included.
# The test runner inside the simulator is launchd_sim's, not xcodebuild's; it ends with the run.
stop() {
  pkill -P "$pid" 2> /dev/null || true
  kill "$pid" 2> /dev/null || true
}
trap stop EXIT INT TERM

idle_limit="${SIMPANIN_IDLE_TIMEOUT:-300}"
# In a full run the UI tests start about 3 s after the summary and are never quiet for more than a few.
summary_idle_limit=60
while kill -0 "$pid" 2> /dev/null; do
  if grep -qsE '\*\* TEST (SUCCEEDED|FAILED) \*\*' "$log"; then
    sleep 10  # time to finish writing the result bundle
    break
  fi
  idle=$(( $(date +%s) - $(stat -f %m "$log") ))
  if grep -qsE 'Test run with [0-9]+ tests' "$log" && [ "$idle" -gt "$summary_idle_limit" ]; then
    echo "test.sh: no output for ${summary_idle_limit}s after Swift Testing's summary; stopping xcodebuild" >&2
    break
  fi
  if [ "$idle" -gt "$idle_limit" ]; then
    echo "test.sh: no output for ${idle_limit}s; stopping xcodebuild" >&2
    break
  fi
  sleep 5
done
stop
wait "$pid" 2> /dev/null || true

# Only the names of failed tests: the lines with an issue's details can hold field values.
grep -E 'Test run with [0-9]+ tests|✘ Test .+ failed after|Executed [0-9]+ tests|\*\* TEST|error:' "$log" \
  | sort -u || true
if [ ! -f "$bundle/Info.plist" ] \
  || ! summary=$(xcrun xcresulttool get test-results summary --path "$bundle" 2> /dev/null); then
  echo "test.sh: FAILED, the result bundle is incomplete or unreadable; see $log" >&2
  exit 1
fi
echo "$summary" | python3 -B -c '
import json, sys
s = json.load(sys.stdin)
total, failed = s.get("totalTestCount", 0), s.get("failedTests", 0)
passed, skipped = s.get("passedTests", 0), s.get("skippedTests", 0)
print(f"test.sh: {total} tests: {passed} passed, {failed} failed, {skipped} skipped")
if total == 0:
    sys.exit("test.sh: FAILED, no test ran: check the --only filter")
if failed or s.get("result") != "Passed":
    sys.exit("test.sh: FAILED")
print("test.sh: PASSED")
'
