#!/bin/bash
# Runs the app's tests for a pushed commit on this Mac and posts the result to GitHub as the commit status
# "App tests (Mac)", which the pull request shows. GitHub's hosted macOS runners failed on their own
# machines more often than on the tests, and the Mac runs the suite without those failures.
#   scripts/ci-mac.sh <branch or commit>
# The pre-push hook starts it as you push, when turned on (CONTRIBUTING.md); by hand, it reruns a commit.
# It only tests a commit that a branch on origin points at, so a fork's commit never runs here.
# It tests the commit in a fresh worktree under build/ci, so the checkout you work in is never touched, on
# its own "iPhone 17 CI" simulator, so it never shares one with a local test.sh run. One run at a time: a
# newer one stops the one going. Only the status line reaches GitHub; the logs stay in build/ci, the newest
# five runs of them. SIMPANIN_CI_WAIT (seconds, default 120) is how long it waits for the push to land, and
# SIMPANIN_CI_STOP_WAIT (default 120) how long for the run going to stop before it's killed, and
# SIMPANIN_CI_LIMIT (default 7200) how long a run may take before it's stopped with an error.
# The status is success when the tests passed, failure when some failed, and error for anything else: a
# stop, a hang, a lost simulator, or a run killed outright, which the next run marks as interrupted.
set -uo pipefail

context="App tests (Mac)"
simulator_name="iPhone 17 CI"
# The runtime test.sh picks its simulator on; move both together.
runtime="com.apple.CoreSimulator.SimRuntime.iOS-27-0"
# A push from an app (Xcode, a Git client) starts the hook without Homebrew's folder on PATH. Last, so the
# PATH it was given still comes first.
PATH="$PATH:/opt/homebrew/bin:/usr/local/bin"

post() {  # sha, state, description (GitHub keeps 140 characters); three tries, as the network can blink
  local try
  for try in 1 2 3; do
    gh api "repos/{owner}/{repo}/statuses/$1" -f state="$2" -f context="$context" \
      -f description="${3:0:140}" > /dev/null && return 0
    [ "$try" -lt 3 ] && sleep $((try * 2))
  done
  return 1
}

running() {  # a ci-mac.sh run that hasn't exited: a zombie's pid still answers kill -0, a reused one anything
  ps -p "$1" -o stat=,command= 2> /dev/null | grep -v '^Z' | grep -qE '(^|[ /])bash .*ci-mac\.sh'
}

# Kills a test.sh process group left by a run that can't stop it any more, only while it's still test.sh:
# after a crash its number can belong to something else.
kill_tests() {
  [ -n "${1:-}" ] && pgrep -g "$1" -f 'scripts/test\.sh' > /dev/null && kill -KILL -- "-$1" 2> /dev/null
}

# Written whole or not at all, so a newer run never reads it half written.
write_pid_file() {
  echo "$*" > "$pid_file.$$" && mv -f "$pid_file.$$" "$pid_file"
}

# Whatever happens once pending is posted, the commit gets a final state, so it never stays pending.
finish() {
  trap '' USR1 INT TERM HUP ALRM  # nothing may cut this short
  [ -n "$timer" ] && { kill -KILL "$timer"; wait "$timer"; } 2> /dev/null  # waited, so bash says nothing
  # test.sh runs in a process group of its own, xcodebuild with it; one stuck in a trap gets 10 s. Before
  # the post, which can hang on the network: a newer run that gives up waiting kills this run, not its tests.
  if [ -n "$group" ]; then
    kill -TERM -- "-$group" 2> /dev/null
    ( sleep 10; kill -KILL -- "-$group" 2> /dev/null ) &
    killer=$!
    wait "$group" 2> /dev/null
    # test.sh sends xcodebuild TERM and ends without waiting; one that ignores it gets the same 10 s.
    for _ in $(seq 20); do pgrep -g "$group" > /dev/null || break; sleep 0.5; done
    kill -KILL -- "-$group" 2> /dev/null
    { kill -KILL "$killer"; wait "$killer"; } 2> /dev/null  # it ignores TERM, as this function does
  fi
  if [ -n "$pending" ] && [ -z "$final" ]; then
    post "$sha" error "$reason" || echo "ci-mac: couldn't post the error status for $short" >&2
  fi
  # A booted simulator holds about 2 GB of the Mac's memory.
  [ -n "$simulator" ] && xcrun simctl shutdown "$simulator" > /dev/null 2>&1
  [ -d "$tree/build" ] && find "$tree/build" -maxdepth 1 -name 'test-*' -exec mv {} "$results/" \;
  git worktree remove --force "$tree" 2> /dev/null
  rm -rf "$tree"
  git worktree prune
  ls -1dt build/ci/20*-* 2> /dev/null | tail -n +6 | while read -r old_run; do rm -rf "$old_run"; done
  { read -r owner _ < "$pid_file"; } 2> /dev/null && [ "$owner" = $$ ] && rm -f "$pid_file"
}

# Called holding the lock. Stops the run going, if any, and waits for it to post its error and clean up, so
# that error can't land after this run's pending on the same commit. If it doesn't stop, this run kills it
# and its tests and posts for it. A run that died without finishing (killed outright, the Mac restarted)
# left its commit pending, so that commit is marked interrupted.
take_over() {
  local old old_sha old_group stop_wait
  { read -r old old_sha old_group < "$pid_file"; } 2> /dev/null || return 0
  [ "$old" != $$ ] || return 0
  if running "$old"; then
    echo "ci-mac: stopping the run going (${old_sha:0:7})"
    kill -USR1 "$old" 2> /dev/null
    stop_wait="${SIMPANIN_CI_STOP_WAIT:-120}"
    for _ in $(seq $((stop_wait * 2))); do running "$old" || return 0; sleep 0.5; done
    # Stuck in a command, where bash holds the signal until it ends. Its tests first, while test.sh still
    # marks the group; then its children, so a status post it has under way can't land after the error below.
    kill_tests "$old_group"
    pkill -KILL -P "$old" 2> /dev/null
    kill -KILL "$old" 2> /dev/null
    # Only if it hadn't posted its result meanwhile: it rewrites the pid file without the commit once it has.
    { read -r old old_sha old_group < "$pid_file"; } 2> /dev/null && [ -n "${old_sha:-}" ] \
      && post "$old_sha" error "stopped, a newer run started; rerun: scripts/ci-mac.sh ${old_sha:0:7}"
  elif [ -n "${old_sha:-}" ]; then
    kill_tests "$old_group"
    post "$old_sha" error "interrupted (killed, or the Mac restarted); rerun: scripts/ci-mac.sh ${old_sha:0:7}" \
      || true
  fi
}

main() {
  cd "$(dirname "$0")/.." || exit 2
  # A push from a linked worktree runs from the main one, so one pid file and one simulator serve them all.
  cd "$(git rev-parse --path-format=absolute --git-common-dir)/.." || exit 2

  [ $# -eq 1 ] || { echo "usage: scripts/ci-mac.sh <branch or commit>" >&2; exit 2; }
  sha=$(git rev-parse --verify --quiet "$1^{commit}") || { echo "ci-mac: '$1' isn't a commit here" >&2; exit 2; }
  short="${sha:0:7}"
  command -v gh > /dev/null || { echo "ci-mac: gh isn't installed, so nothing can be posted for $short" >&2; exit 1; }
  mkdir -p build/ci
  pid_file=build/ci/run.pid
  tree=build/ci/tree
  pending="" final="" group="" timer="" simulator="" reason="stopped on the Mac"

  # The hook starts this before git sends the commit, so wait for a branch on origin to point at it. A push
  # that's refused never gets there, and neither does a fork's commit: nothing runs or is posted for them.
  deadline=$(( $(date +%s) + ${SIMPANIN_CI_WAIT:-120} ))
  until git ls-remote --heads origin 2> /dev/null | grep -q "^$sha"; do
    if [ "$(date +%s)" -ge "$deadline" ]; then
      echo "ci-mac: no branch on origin points at $short (not pushed, refused, or not ours); nothing posted" >&2
      exit 1
    fi
    sleep 2
  done

  results="build/ci/$(date +%Y%m%d-%H%M%S)-$short"
  mkdir -p "$results"
  # Two pushes seconds apart would both find the same run going, both stop it, and both run on one
  # simulator. The kernel's lock lets one take over at a time, and goes with its holder however it ends.
  # bash has no flock, so python takes it on bash's descriptor 9 and it stays held while bash keeps 9 open.
  exec 9> build/ci/lock
  python3 -c 'import fcntl; fcntl.flock(9, fcntl.LOCK_EX)' || exit 1
  take_over
  # Before the pid file names this run, so a newer one's stop always finds the traps set.
  trap finish EXIT
  trap 'reason="stopped, a newer run started; rerun: scripts/ci-mac.sh $short"; exit 1' USR1
  trap 'exit 130' INT TERM HUP
  limit="${SIMPANIN_CI_LIMIT:-7200}"
  trap 'reason="no result after $((limit / 60)) min; rerun: scripts/ci-mac.sh $short"; exit 1' ALRM
  write_pid_file "$$ $sha"
  python3 -c 'import fcntl; fcntl.flock(9, fcntl.LOCK_UN)'
  exec 9>&-

  # Set first: a signal during the post exits before the line after it, and the error must still go out.
  pending=yes reason="couldn't post the pending status"
  post "$sha" pending "Running on the Mac" || { echo "ci-mac: $reason for $short" >&2; exit 1; }
  reason="stopped on the Mac"

  simulator=$(xcrun simctl list devices available -j | python3 -B -c '
import json, sys
for runtime, devices in json.load(sys.stdin)["devices"].items():
    if runtime == sys.argv[1]:
        for device in devices:
            if device["name"] == sys.argv[2]:
                print(device["udid"])
                raise SystemExit
' "$runtime" "$simulator_name")
  if [ -z "$simulator" ] && ! simulator=$(xcrun simctl create "$simulator_name" "iPhone 17" "$runtime"); then
    reason="no $simulator_name simulator on iOS 27.0"
    echo "ci-mac: $reason" >&2
    exit 1
  fi

  # A run killed outright (SIGKILL, power loss) leaves its worktree behind.
  git worktree remove --force "$tree" 2> /dev/null
  rm -rf "$tree"
  git worktree prune
  git worktree add --quiet --detach "$tree" "$sha" || { reason="couldn't check out $short"; exit 1; }

  echo "ci-mac: testing $short on $simulator_name; log in $results/test.log"
  caffeinate -i -w $$ &  # no idle sleep while it runs; closing the lid still sleeps
  # In the background, so a signal reaches the traps above at once rather than after the run, and in a
  # process group of its own, so stopping it stops xcodebuild too.
  ( cd "$tree" && SIMPANIN_SIMULATOR="$simulator" \
    exec python3 -c 'import os, sys; os.setsid(); os.execvp(sys.argv[1], sys.argv[1:])' scripts/test.sh ) \
    > "$results/test.log" 2>&1 &
  group=$!
  # test.sh only notices a run that goes quiet; one that hangs before xcodebuild, or never stops printing,
  # would leave the commit pending for good.
  # It checks this run is still alive and goes with it: a run killed outright would otherwise leave it to
  # signal whatever process takes this number.
  ( end=$(( $(date +%s) + limit ))
    while running $$; do
      [ "$(date +%s)" -ge "$end" ] && { kill -ALRM $$; exit; }
      sleep 2
    done ) &
  timer=$!
  write_pid_file "$$ $sha $group"
  wait "$group"
  status=$?
  group=""

  counts=$(grep -E '^test\.sh: [0-9]+ tests:' "$results/test.log" | tail -n 1)
  counts="${counts#test.sh: }"
  failed=$(echo "$counts" | sed -nE 's/.* ([0-9]+) failed.*/\1/p')
  if [ "$status" -eq 0 ]; then
    state=success
    description="$counts"
  elif [ "${failed:-0}" -gt 0 ]; then
    state=failure
    description="$counts"
  else
    # The run itself went wrong (stopped, hung, simulator lost, no test ran), not a test.
    state=error
    last=$(grep '^test\.sh: FAILED' "$results/test.log" | tail -n 1)
    description="${last#test.sh: }"
    description="${description:-${counts:-test.sh exited with $status}}"
  fi
  echo "ci-mac: $short $state: $description"
  trap '' USR1 INT TERM HUP ALRM  # a signal now would put an error over the result GitHub already has
  if post "$sha" "$state" "$description"; then
    final=yes
    write_pid_file "$$"  # finished: if this run dies now, the next one has nothing to mark interrupted
  else
    echo "ci-mac: couldn't post the result ($state: $description); rerun: scripts/ci-mac.sh $short" >&2
    reason="couldn't post the result; rerun: scripts/ci-mac.sh $short"
    exit 1
  fi
  [ "$state" = success ]
}

# All of it is read before anything runs, so editing this file during a 45-minute run can't change it. On
# one line, so bash has read the exit too.
main "$@"; exit
