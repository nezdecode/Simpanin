#!/usr/bin/env python3
# Tests scripts/ci-mac.sh and scripts/hooks/pre-push, which run the app's tests on the maintainer's Mac and
# post the result to GitHub as a commit status. Each case runs in a temporary clone with a bare origin, a
# fake gh, xcrun and caffeinate on PATH that log their calls, and commits whose scripts/test.sh is a stub, so
# no simulator runs and nothing reaches GitHub. Run by scripts/ci-checks.sh; by hand with:
#   python3 scripts/test-ci-mac.py

import os
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import unittest

sys.dont_write_bytecode = True
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# test.sh's last lines, as the real one prints them. "stubborn" ignores TERM, as a test.sh stuck in a trap.
STUB_TEST_SH = r'''#!/bin/bash
echo $$ > "$FAKE_DIR/test-sh.pid"
# Other stubs of this test still running, never a real test.sh elsewhere on the Mac.
others=0
for pid in $(cat "$FAKE_DIR/test-sh.pids" 2> /dev/null); do
  ps -p "$pid" -o stat= 2> /dev/null | grep -qv '^Z' && others=$((others + 1))
done
echo $$ >> "$FAKE_DIR/test-sh.pids"
echo "simulator=$SIMPANIN_SIMULATOR others=$others" >> "$FAKE_DIR/test-sh.log"
case "${FAKE_TEST_MODE:-pass}" in
  pass) echo "test.sh: 786 tests: 785 passed, 0 failed, 1 skipped"; echo "test.sh: PASSED" ;;
  fail) echo "test.sh: 786 tests: 780 passed, 6 failed, 0 skipped"; echo "test.sh: FAILED"; exit 1 ;;
  lies) echo "test.sh: 786 tests: 785 passed, 0 failed, 1 skipped"; echo "test.sh: PASSED"; exit 1 ;;
  sleep) sleep "${FAKE_SLEEP:-30}"; echo "test.sh: 786 tests: 785 passed, 0 failed, 1 skipped"; echo "test.sh: PASSED" ;;
  broken) echo "test.sh: FAILED, xcodebuild was stopped; see build/test-1/xcodebuild.log"; exit 1 ;;
  # Ends on TERM, as test.sh does, but leaves a stand-in for an xcodebuild that ignores it.
  leaves) (trap '' TERM; exec sleep 300) & echo $! | tee "$FAKE_DIR/xcodebuild.pid" >> "$FAKE_DIR/children.pids"
    sleep 300 ;;
  # A stand-in for an xcodebuild that ignores TERM too, in the same process group, which must die with it.
  stubborn) (trap '' TERM; exec sleep 300) & echo $! | tee "$FAKE_DIR/xcodebuild.pid" >> "$FAKE_DIR/children.pids"
    trap 'echo TERM >> "$FAKE_DIR/test-sh.log"' TERM; while true; do sleep 1; done ;;
esac
'''

FAKE_GH = r'''#!/bin/bash
# gh api repos/{owner}/{repo}/statuses/<sha> -f state=... -f context=... -f description=...
echo $$ >> "$FAKE_DIR/gh.pids"  # killed by the tests' cleanup too
[ "$1" = api ] || exit 1
case "$*" in
  *state=pending*)
    [ "${FAKE_GH_SLOW:-}" = pending ] && { touch "$FAKE_DIR/posting"; sleep "${FAKE_GH_SLOW_SECONDS:-3}"; }
    ;;
  *)
    [ "${FAKE_GH_SLOW:-}" = final ] && { touch "$FAKE_DIR/posting"; sleep "${FAKE_GH_SLOW_SECONDS:-3}"; }
    [ -n "${FAKE_GH_FAIL_FINAL:-}" ] && exit 1
    failed=$(cat "$FAKE_DIR/gh-failed" 2> /dev/null || echo 0)
    if [ "$failed" -lt "${FAKE_GH_FAIL_FINAL_TIMES:-0}" ]; then echo $((failed + 1)) > "$FAKE_DIR/gh-failed"; exit 1; fi
    ;;
esac
# Logged once it has gone through, as GitHub would have it.
echo "$*" >> "$FAKE_DIR/gh.log"
exit 0
'''

FAKE_XCRUN = r'''#!/bin/bash
echo "$*" >> "$FAKE_DIR/xcrun.log"
case "$*" in
  "simctl list devices available -j")
    if [ -n "${FAKE_NO_CI_SIMULATOR:-}" ] && [ ! -e "$FAKE_DIR/created" ]; then
      echo '{"devices": {"com.apple.CoreSimulator.SimRuntime.iOS-27-0": [{"name": "iPhone 17", "udid": "LOCAL"}]}}'
    else
      echo '{"devices": {"com.apple.CoreSimulator.SimRuntime.iOS-27-0": [{"name": "iPhone 17", "udid": "LOCAL"}, {"name": "iPhone 17 CI", "udid": "CI-UDID"}]}}'
    fi
    ;;
  "simctl shutdown"*) sleep "${FAKE_SHUTDOWN_SECONDS:-0}" ;;
  "simctl create"*)
    [ -n "${FAKE_CREATE_FAILS:-}" ] && { echo "Invalid runtime" >&2; exit 1; }
    touch "$FAKE_DIR/created"; echo "NEW-UDID"
    ;;
esac
'''

FAKE_CAFFEINATE = '#!/bin/bash\nexit 0\n'


def write(path, text, mode=0o755):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w') as f:
        f.write(text)
    os.chmod(path, mode)


def git(cwd, *args):
    return subprocess.run(['git', *args], cwd=cwd, check=True, capture_output=True, text=True).stdout.strip()


class Clone:
    """A clone with a bare origin, ci-mac.sh and the hook copied in, and the fakes on PATH. Its first two
    commits are pushed, each as the head of a branch."""

    def __init__(self):
        self.dir = tempfile.mkdtemp(prefix='ci-mac-')
        self.fakes = os.path.join(self.dir, 'fakes')
        self.work = os.path.join(self.dir, 'work')
        self.runs = []
        origin = os.path.join(self.dir, 'origin.git')
        subprocess.run(['git', 'init', '-q', '--bare', origin], check=True)
        subprocess.run(['git', 'clone', '-q', origin, self.work], check=True, capture_output=True)
        git(self.work, 'config', 'user.name', 'Test')
        git(self.work, 'config', 'user.email', 'test@example.com')
        git(self.work, 'config', 'core.hooksPath', '/dev/null')
        write(os.path.join(self.work, 'scripts', 'test.sh'), STUB_TEST_SH)
        write(os.path.join(self.work, '.gitignore'), 'build/\n', 0o644)
        self.first = self.commit('first')
        self.second = self.commit('second')
        self.push(self.first, 'ci/first')
        self.push(self.second, 'ci/second')
        # The scripts under test, untracked, as on the maintainer's Mac before they're committed.
        shutil.copy(os.path.join(ROOT, 'scripts', 'ci-mac.sh'), os.path.join(self.work, 'scripts', 'ci-mac.sh'))
        os.makedirs(os.path.join(self.work, 'scripts', 'hooks'))
        shutil.copy(os.path.join(ROOT, 'scripts', 'hooks', 'pre-push'), os.path.join(self.work, 'scripts', 'hooks'))
        write(os.path.join(self.fakes, 'gh'), FAKE_GH)
        write(os.path.join(self.fakes, 'xcrun'), FAKE_XCRUN)
        write(os.path.join(self.fakes, 'caffeinate'), FAKE_CAFFEINATE)

    def commit(self, name):
        write(os.path.join(self.work, f'{name}.txt'), f'{name}\n', 0o644)
        git(self.work, 'add', '-A', '--', '.gitignore', 'scripts/test.sh', f'{name}.txt')
        git(self.work, 'commit', '-q', '-m', name)
        return git(self.work, 'rev-parse', 'HEAD')

    def push(self, sha, branch):
        git(self.work, 'push', '-q', 'origin', f'{sha}:refs/heads/{branch}')

    def env(self, **extra):
        env = dict(os.environ, PATH=self.fakes + os.pathsep + os.environ['PATH'], FAKE_DIR=self.fakes,
                   SIMPANIN_CI_WAIT='3')
        env.pop('GITHUB_ACTIONS', None)
        env.update(extra)
        return env

    def ci_mac(self, *args, cwd=None, **extra):
        return subprocess.run(['scripts/ci-mac.sh', *args], cwd=cwd or self.work, env=self.env(**extra),
                              capture_output=True, text=True, timeout=90)

    def start_ci_mac(self, *args, **extra):
        run = subprocess.Popen(['scripts/ci-mac.sh', *args], cwd=self.work, env=self.env(**extra),
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.runs.append(run)
        return run

    def log(self, name):
        path = os.path.join(self.fakes, name)
        if not os.path.exists(path):
            return []
        with open(path) as f:
            return f.read().splitlines()

    def statuses(self):
        """(sha, state, description) for each status posted, in order."""
        posted = []
        for line in self.log('gh.log'):
            if '/statuses/' not in line:
                continue
            sha = line.split('/statuses/')[1].split()[0]
            state = line.split('state=')[1].split()[0]
            description = line.split('description=')[1] if 'description=' in line else ''
            posted.append((sha, state, description))
        return posted

    def wait_for(self, condition, seconds=20):
        deadline = time.time() + seconds
        while time.time() < deadline:
            if condition():
                return True
            time.sleep(0.2)
        return False

    def wait_for_file(self, name):
        return self.wait_for(lambda: os.path.exists(os.path.join(self.fakes, name)))

    def test_sh_pid(self):
        with open(os.path.join(self.fakes, 'test-sh.pid')) as f:
            return int(f.read())

    def worktrees(self):
        return [line for line in git(self.work, 'worktree', 'list').splitlines() if line]

    def remove(self):
        for run in self.runs:
            if run.poll() is None:
                run.kill()
            run.wait()
        # Every stub test.sh started, so a run that left one behind can't leave it running after the test.
        for pid in self.log('test-sh.pids') + self.log('gh.pids') + self.log('children.pids'):
            try:
                os.kill(int(pid), signal.SIGKILL)
            except OSError:
                pass
        shutil.rmtree(self.dir, ignore_errors=True)


def alive(pid):
    try:
        os.kill(pid, 0)
    except OSError:
        return False
    # A zombie still answers kill -0.
    state = subprocess.run(['ps', '-p', str(pid), '-o', 'stat='], capture_output=True, text=True).stdout.strip()
    return bool(state) and not state.startswith('Z')


class CIMacTests(unittest.TestCase):
    def setUp(self):
        self.clone = Clone()
        self.addCleanup(self.clone.remove)

    def test_refuses_an_argument_that_is_not_a_commit(self):
        for args in ([], ['no-such-branch'], [self.clone.first, self.clone.second]):
            result = self.clone.ci_mac(*args)
            self.assertEqual(result.returncode, 2, args)
        self.assertEqual(self.clone.log('gh.log'), [])

    def test_waits_until_github_has_the_commit(self):
        third = self.clone.commit('third')
        run = self.clone.start_ci_mac(third, SIMPANIN_CI_WAIT='30')
        time.sleep(3)
        self.assertEqual(self.clone.statuses(), [])
        self.clone.push(third, 'ci/third')
        run.wait(timeout=30)
        self.assertEqual(run.returncode, 0)
        self.assertEqual([state for _, state, _ in self.clone.statuses()], ['pending', 'success'])

    def test_posts_nothing_when_the_push_never_lands(self):
        third = self.clone.commit('third')
        result = self.clone.ci_mac(third)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(self.clone.statuses(), [])
        self.assertFalse(os.path.exists(os.path.join(self.clone.fakes, 'test-sh.pid')))

    def test_refuses_a_commit_no_branch_on_origin_points_at(self):
        # On origin, but only inside another branch's history, as a fork's commit or an old one would be.
        third = self.clone.commit('third')
        fourth = self.clone.commit('fourth')
        self.clone.push(fourth, 'ci/fourth')
        result = self.clone.ci_mac(third)
        self.assertEqual(result.returncode, 1)
        self.assertIn('no branch on origin points at', result.stderr)
        self.assertEqual(self.clone.statuses(), [])

    def test_success_only_when_test_sh_exits_zero(self):
        passed = self.clone.ci_mac(self.clone.first)
        self.assertEqual(passed.returncode, 0, passed.stdout + passed.stderr)
        self.assertNotIn('Killed', passed.stdout + passed.stderr)
        self.assertEqual(self.clone.statuses()[-1],
                         (self.clone.first, 'success', '786 tests: 785 passed, 0 failed, 1 skipped'))
        lied = self.clone.ci_mac(self.clone.second, FAKE_TEST_MODE='lies')
        self.assertEqual(lied.returncode, 1)
        self.assertEqual(self.clone.statuses()[-1][:2], (self.clone.second, 'error'))

    def test_posts_failure_with_the_last_line_when_tests_fail(self):
        result = self.clone.ci_mac(self.clone.first, FAKE_TEST_MODE='fail')
        self.assertEqual(result.returncode, 1)
        self.assertEqual(self.clone.statuses(), [
            (self.clone.first, 'pending', 'Running on the Mac'),
            (self.clone.first, 'failure', '786 tests: 780 passed, 6 failed, 0 skipped'),
        ])
        self.assertEqual(len(self.clone.worktrees()), 1)

    def test_posts_error_and_cleans_up_when_stopped_by_a_signal(self):
        run = self.clone.start_ci_mac(self.clone.first, FAKE_TEST_MODE='sleep')
        self.assertTrue(self.clone.wait_for_file('test-sh.pid'), 'test.sh never started')
        test_sh = self.clone.test_sh_pid()
        run.send_signal(signal.SIGTERM)
        run.wait(timeout=20)
        self.assertNotEqual(run.returncode, 0)
        self.assertEqual(self.clone.statuses()[-1], (self.clone.first, 'error', 'stopped on the Mac'))
        self.assertTrue(self.clone.wait_for(lambda: not alive(test_sh), 10), 'test.sh still running')
        self.assertEqual(len(self.clone.worktrees()), 1)
        self.assertFalse(os.path.exists(os.path.join(self.clone.work, 'build', 'ci', 'run.pid')))

    def test_a_newer_run_stops_the_older_one_and_says_so(self):
        older = self.clone.start_ci_mac(self.clone.first, FAKE_TEST_MODE='stubborn')
        self.assertTrue(self.clone.wait_for_file('test-sh.pid'), 'older run never started')
        older_test_sh = self.clone.test_sh_pid()
        newer = self.clone.ci_mac(self.clone.second)
        older.wait(timeout=30)
        self.assertEqual(newer.returncode, 0, newer.stdout + newer.stderr)
        self.assertFalse(alive(older_test_sh), "the older run's test.sh outlived it")
        # The newer run's test.sh found no other one running.
        self.assertEqual(self.clone.log('test-sh.log')[-1], 'simulator=CI-UDID others=0')
        statuses = self.clone.statuses()
        older_error = statuses.index((self.clone.first, 'error',
                                      f'stopped, a newer run started; rerun: scripts/ci-mac.sh {self.clone.first[:7]}'))
        self.assertLess(older_error, statuses.index((self.clone.second, 'pending', 'Running on the Mac')))
        self.assertEqual(statuses[-1][:2], (self.clone.second, 'success'))

    def test_a_stale_pid_file_stops_nothing(self):
        sleeper = subprocess.Popen(['sleep', '30'])
        self.addCleanup(sleeper.wait)
        self.addCleanup(sleeper.kill)
        write(os.path.join(self.clone.work, 'build', 'ci', 'run.pid'), f'{sleeper.pid}\n', 0o644)
        result = self.clone.ci_mac(self.clone.first)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIsNone(sleeper.poll(), 'killed a process that was not ci-mac.sh')

    def test_a_signal_during_the_pending_post_still_ends_in_error(self):
        run = self.clone.start_ci_mac(self.clone.first, FAKE_GH_SLOW='pending', FAKE_TEST_MODE='sleep')
        self.assertTrue(self.clone.wait_for_file('posting'), 'pending never posted')
        run.send_signal(signal.SIGTERM)
        run.wait(timeout=20)
        self.assertEqual([state for _, state, _ in self.clone.statuses()], ['pending', 'error'])

    def test_a_signal_during_the_final_post_keeps_the_result(self):
        run = self.clone.start_ci_mac(self.clone.first, FAKE_GH_SLOW='final')
        self.assertTrue(self.clone.wait_for_file('posting'), 'the result never posted')
        run.send_signal(signal.SIGTERM)
        run.wait(timeout=20)
        self.assertEqual([state for _, state, _ in self.clone.statuses()], ['pending', 'success'])

    def test_says_so_when_the_result_cannot_be_posted(self):
        result = self.clone.ci_mac(self.clone.first, FAKE_GH_FAIL_FINAL='1')
        self.assertEqual(result.returncode, 1)
        self.assertIn("couldn't post", result.stdout + result.stderr)
        self.assertIn('785 passed', result.stdout + result.stderr)

    def test_a_run_from_a_linked_worktree_uses_the_main_ones_folder(self):
        linked = os.path.join(self.clone.dir, 'linked')
        git(self.clone.work, 'worktree', 'add', '-q', '--detach', linked, self.clone.first)
        shutil.copy(os.path.join(self.clone.work, 'scripts', 'ci-mac.sh'), os.path.join(linked, 'scripts'))
        result = self.clone.ci_mac(self.clone.first, cwd=linked)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(os.path.exists(os.path.join(linked, 'build')))
        self.assertTrue(os.path.isdir(os.path.join(self.clone.work, 'build', 'ci')))

    def test_two_runs_starting_together_never_both_run(self):
        third = self.clone.commit('third')
        self.clone.push(third, 'ci/third')
        older = self.clone.start_ci_mac(self.clone.first, FAKE_TEST_MODE='sleep')
        self.assertTrue(self.clone.wait_for_file('test-sh.pid'), 'older run never started')
        newer = [self.clone.start_ci_mac(sha, FAKE_TEST_MODE='sleep', FAKE_SLEEP='3')
                 for sha in (self.clone.second, third)]
        for run in [older, *newer]:
            run.wait(timeout=60)
        starts = self.clone.log('test-sh.log')
        self.assertGreaterEqual(len(starts), 2, starts)
        self.assertTrue(all(line.endswith('others=0') for line in starts), starts)

    def test_a_run_that_wont_stop_is_killed_and_its_error_posted_for_it(self):
        # Stuck in gh, where bash holds the signal until the command ends.
        older = self.clone.start_ci_mac(self.clone.first, FAKE_GH_SLOW='pending', FAKE_GH_SLOW_SECONDS='20')
        self.assertTrue(self.clone.wait_for_file('posting'), 'older run never posted')
        started = time.time()
        newer = self.clone.ci_mac(self.clone.second, SIMPANIN_CI_STOP_WAIT='2')
        self.assertLess(time.time() - started, 15, 'waited for the older run instead of killing it')
        older.wait(timeout=20)
        self.assertEqual(newer.returncode, 0, newer.stdout + newer.stderr)
        older_states = [(state, description) for sha, state, description in self.clone.statuses()
                        if sha == self.clone.first]
        self.assertEqual(older_states[-1][0], 'error', older_states)
        self.assertIn('a newer run started', older_states[-1][1])
        time.sleep(max(0, started + 21 - time.time()))  # the killed gh would have posted by now
        self.assertEqual([s for s in self.clone.statuses() if s[0] == self.clone.first][-1][1], 'error')

    def test_a_run_that_wont_stop_has_all_its_tests_killed(self):
        # Stuck in its cleanup, waiting for a test.sh that ignores TERM.
        older = self.clone.start_ci_mac(self.clone.first, FAKE_TEST_MODE='stubborn')
        self.assertTrue(self.clone.wait_for_file('xcodebuild.pid'), 'older run never started')
        xcodebuild = int(self.clone.log('xcodebuild.pid')[0])
        newer = self.clone.ci_mac(self.clone.second, SIMPANIN_CI_STOP_WAIT='2')
        older.wait(timeout=20)
        self.assertEqual(newer.returncode, 0, newer.stdout + newer.stderr)
        self.assertFalse(alive(xcodebuild), "the older run's xcodebuild outlived it")

    def test_a_stopped_run_leaves_no_test_process_behind(self):
        run = self.clone.start_ci_mac(self.clone.first, FAKE_TEST_MODE='leaves')
        self.assertTrue(self.clone.wait_for_file('xcodebuild.pid'), 'test.sh never started')
        xcodebuild = int(self.clone.log('xcodebuild.pid')[0])
        run.send_signal(signal.SIGTERM)
        run.wait(timeout=30)
        self.assertFalse(alive(xcodebuild), 'xcodebuild outlived the run')

    def test_a_run_with_no_result_in_time_is_stopped_with_an_error(self):
        result = self.clone.ci_mac(self.clone.first, FAKE_TEST_MODE='sleep', SIMPANIN_CI_LIMIT='3')
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertEqual(self.clone.statuses()[-1][:2], (self.clone.first, 'error'))
        self.assertIn('no result after', self.clone.statuses()[-1][2])
        self.assertFalse(alive(self.clone.test_sh_pid()), 'test.sh still running')

    def test_a_run_killed_outright_leaves_no_timer_behind(self):
        # Its timer would otherwise signal whatever process takes its number when the limit runs out.
        self.clone.start_ci_mac(self.clone.first, FAKE_TEST_MODE='sleep')
        self.assertTrue(self.clone.wait_for_file('test-sh.pid'), 'test.sh never started')
        with open(os.path.join(self.clone.work, 'build', 'ci', 'run.pid')) as f:
            os.kill(int(f.read().split()[0]), signal.SIGKILL)
        left = lambda: subprocess.run(['pgrep', '-f', f'ci-mac.sh {self.clone.first}'],
                                      capture_output=True, text=True).stdout.split()
        self.assertTrue(self.clone.wait_for(lambda: not left(), 10), f'still running: {left()}')

    def test_marks_a_run_killed_outright_as_interrupted(self):
        dead = subprocess.Popen(['true'])
        dead.wait()
        write(os.path.join(self.clone.work, 'build', 'ci', 'run.pid'), f'{dead.pid} {self.clone.first}\n', 0o644)
        result = self.clone.ci_mac(self.clone.second)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.clone.statuses()[0][:2], (self.clone.first, 'error'))
        self.assertIn('interrupted', self.clone.statuses()[0][2])

    def test_a_finished_run_is_not_marked_interrupted(self):
        self.clone.ci_mac(self.clone.first)
        with open(os.path.join(self.clone.work, 'build', 'ci', 'run.pid'), 'w') as f:
            f.write('999999\n')  # a run that posted its result, then died before removing the file
        self.clone.ci_mac(self.clone.second)
        self.assertEqual([state for sha, state, _ in self.clone.statuses() if sha == self.clone.first],
                         ['pending', 'success'])
        self.assertFalse([s for s in self.clone.statuses() if 'interrupted' in s[2]], self.clone.statuses())

    def test_never_kills_a_process_group_that_is_no_longer_test_sh(self):
        dead = subprocess.Popen(['true'])
        dead.wait()
        other = subprocess.Popen(['sleep', '30'], start_new_session=True)
        self.addCleanup(other.wait)
        self.addCleanup(other.kill)
        write(os.path.join(self.clone.work, 'build', 'ci', 'run.pid'),
              f'{dead.pid} {self.clone.first} {other.pid}\n', 0o644)
        result = self.clone.ci_mac(self.clone.second)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIsNone(other.poll(), 'killed a process group that was not test.sh')

    def test_kills_the_tests_of_a_run_killed_outright(self):
        dead = subprocess.Popen(['true'])
        dead.wait()
        tests = os.path.join(self.clone.dir, 'orphan')
        write(os.path.join(tests, 'scripts', 'test.sh'), '#!/bin/bash\nsleep 30\n')
        orphan = subprocess.Popen(['scripts/test.sh'], cwd=tests, start_new_session=True)
        self.addCleanup(orphan.wait)
        self.addCleanup(orphan.kill)
        write(os.path.join(self.clone.work, 'build', 'ci', 'run.pid'),
              f'{dead.pid} {self.clone.first} {orphan.pid}\n', 0o644)
        result = self.clone.ci_mac(self.clone.second)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue(self.clone.wait_for(lambda: orphan.poll() is not None, 5), "the dead run's tests still run")

    def test_a_run_that_finishes_while_being_stopped_keeps_its_result(self):
        # Its result is posted while the newer run waits for it, then its cleanup outlasts the wait.
        older = self.clone.start_ci_mac(self.clone.first, FAKE_GH_SLOW='final', FAKE_SHUTDOWN_SECONDS='10')
        self.assertTrue(self.clone.wait_for_file('posting'), 'the result never posted')
        newer = self.clone.ci_mac(self.clone.second, SIMPANIN_CI_STOP_WAIT='5')
        older.wait(timeout=20)
        self.assertEqual(newer.returncode, 0, newer.stdout + newer.stderr)
        self.assertEqual([state for sha, state, _ in self.clone.statuses() if sha == self.clone.first],
                         ['pending', 'success'])
        self.assertFalse([line for line in self.clone.log('gh.log') if 'statuses/ ' in line], 'posted to no commit')

    def test_shuts_the_ci_simulator_down_after_a_run(self):
        self.clone.ci_mac(self.clone.first)
        self.assertIn('simctl shutdown CI-UDID', self.clone.log('xcrun.log'))

    def test_a_stopped_or_broken_run_is_an_error_not_a_failure(self):
        result = self.clone.ci_mac(self.clone.first, FAKE_TEST_MODE='broken')
        self.assertEqual(result.returncode, 1)
        self.assertEqual(self.clone.statuses()[-1],
                         (self.clone.first, 'error', 'FAILED, xcodebuild was stopped; see build/test-1/xcodebuild.log'))

    def test_retries_a_status_post_that_fails(self):
        result = self.clone.ci_mac(self.clone.first, FAKE_GH_FAIL_FINAL_TIMES='2')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.clone.statuses()[-1][:2], (self.clone.first, 'success'))

    def test_creates_the_ci_simulator_when_missing(self):
        result = self.clone.ci_mac(self.clone.first, FAKE_NO_CI_SIMULATOR='1')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue(any(line.startswith('simctl create iPhone 17 CI') for line in self.clone.log('xcrun.log')))
        self.assertEqual(self.clone.log('test-sh.log'), ['simulator=NEW-UDID others=0'])

    def test_runs_on_the_ci_simulator_never_the_local_one(self):
        self.clone.ci_mac(self.clone.first)
        self.assertEqual(self.clone.log('test-sh.log'), ['simulator=CI-UDID others=0'])

    def test_posts_error_when_no_ci_simulator_can_be_made(self):
        result = self.clone.ci_mac(self.clone.first, FAKE_NO_CI_SIMULATOR='1', FAKE_CREATE_FAILS='1')
        self.assertEqual(result.returncode, 1)
        self.assertEqual(self.clone.statuses()[-1][1:], ('error', 'no iPhone 17 CI simulator on iOS 27.0'))
        self.assertFalse(os.path.exists(os.path.join(self.clone.fakes, 'test-sh.pid')))


class DocsOnlyTests(unittest.TestCase):
    """A branch that changes only docs since main is posted as skipped, and anything else runs the tests."""

    SKIPPED = 'Skipped: only docs changed since main'

    def setUp(self):
        self.clone = Clone()
        self.addCleanup(self.clone.remove)
        self.clone.push(self.clone.first, 'main')

    def branch(self, name, *changes, base=None):
        """Commits each change on top of base (main by default) and pushes the last as ci/<name>. A change maps
        paths to their text, or to None to delete them; ('mv', old, new) renames a file."""
        git(self.clone.work, 'checkout', '-q', '--detach', base or self.clone.first)
        for number, change in enumerate(changes):
            if isinstance(change, tuple):
                git(self.clone.work, 'mv', change[1], change[2])
            else:
                for path, text in change.items():
                    if text is None:
                        git(self.clone.work, 'rm', '-q', path)
                    else:
                        write(os.path.join(self.clone.work, path), text, 0o644)
                        git(self.clone.work, 'add', '--', path)
            git(self.clone.work, 'commit', '-q', '-m', f'{name} {number}')
        sha = git(self.clone.work, 'rev-parse', 'HEAD')
        self.clone.push(sha, f'ci/{name}')
        return sha

    def assertSkipped(self, sha):
        result = self.clone.ci_mac(sha)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.clone.statuses(), [(sha, 'success', self.SKIPPED)])
        self.assertFalse(os.path.exists(os.path.join(self.clone.fakes, 'test-sh.pid')))

    def assertRan(self, sha):
        result = self.clone.ci_mac(sha)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.clone.statuses()[-2:], [
            (sha, 'pending', 'Running on the Mac'),
            (sha, 'success', '786 tests: 785 passed, 0 failed, 1 skipped'),
        ])

    def test_skips_a_branch_that_changes_only_docs(self):
        sha = self.branch('docs', {'README.md': 'a\n', '.github/pull_request_template.md': 'b\n'},
                          {'.github/ISSUE_TEMPLATE/bug.md': 'c\n', 'CONTRIBUTING.md': 'd\n'})
        self.assertSkipped(sha)

    def test_runs_a_branch_whose_earlier_commit_changed_code(self):
        sha = self.branch('code-then-docs', {'App.swift': 'let a = 1\n'}, {'README.md': 'a\n'})
        self.assertRan(sha)

    def test_runs_when_a_file_outside_the_allow_list_changed(self):
        for number, path in enumerate(['.github/workflows/app-tests.yml', 'scripts/check.sh', '.swiftlint.yml',
                                       'Simpanin/Resources/Localizable.xcstrings', 'README.txt']):
            with self.subTest(path=path):
                sha = self.branch(f'other-{number}', {'README.md': 'a\n', path: 'x\n'})
                self.assertRan(sha)

    def test_runs_when_markdown_inside_an_app_folder_changed(self):
        # Xcode copies any file under the app's folders into the app, so it isn't only a doc there.
        sha = self.branch('nested', {'Simpanin/Features/README.md': 'a\n'})
        self.assertRan(sha)

    def test_runs_when_a_file_was_renamed_to_markdown(self):
        sha = self.branch('rename', ('mv', 'first.txt', 'first.md'))
        self.assertRan(sha)

    def test_runs_when_main_is_missing_or_nothing_changed(self):
        self.assertRan(self.clone.first)  # main itself: nothing changed
        sha = self.branch('docs', {'README.md': 'a\n'})
        # Inside origin: a push may not delete the branch its HEAD names.
        git(os.path.join(self.clone.dir, 'origin.git'), 'update-ref', '-d', 'refs/heads/main')
        self.assertRan(sha)

    def test_ignores_a_stale_local_origin_main(self):
        git(self.clone.work, 'fetch', '-q', 'origin')
        newer = self.branch('newer-main', {'App.swift': 'let a = 1\n'})
        # Moved inside origin, as another push would: pushing from this clone would update its origin/main too.
        git(os.path.join(self.clone.dir, 'origin.git'), 'update-ref', 'refs/heads/main', newer)
        sha = self.branch('docs', {'README.md': 'a\n'}, base=newer)
        self.assertSkipped(sha)


class PrePushTests(unittest.TestCase):
    """The hook with a fake ci-mac.sh that records how it was started."""

    def setUp(self):
        self.clone = Clone()
        self.addCleanup(self.clone.remove)
        write(os.path.join(self.clone.work, 'scripts', 'ci-mac.sh'),
              '#!/bin/bash\necho "$1 pgid=$(ps -o pgid= -p $$ | tr -d " ") pid=$$" >> "$FAKE_DIR/started"\nsleep 5\n')

    def push(self, lines, remote='origin', enabled=True):
        if enabled:
            git(self.clone.work, 'config', 'simpanin.ciMac', 'true')
        start = time.time()
        result = subprocess.run(['scripts/hooks/pre-push', remote, 'url'], cwd=self.clone.work,
                                env=self.clone.env(), input=''.join(f'{line}\n' for line in lines),
                                capture_output=True, text=True, timeout=30)
        return result, time.time() - start

    def started(self, wait=True):
        path = os.path.join(self.clone.fakes, 'started')
        if wait:
            self.clone.wait_for(lambda: os.path.exists(path), 5)
        if not os.path.exists(path):
            return []
        with open(path) as f:
            return f.read().splitlines()

    def branch(self, name, sha):
        return f'refs/heads/{name} {sha} refs/heads/{name} {"0" * 40}'

    def test_hook_does_nothing_unless_turned_on(self):
        result, _ = self.push([self.branch('ci/x', self.clone.first)], enabled=False)
        self.assertEqual(result.returncode, 0)
        time.sleep(1)
        self.assertEqual(self.started(wait=False), [])

    def test_hook_starts_one_detached_run_and_returns_at_once(self):
        result, seconds = self.push([self.branch('ci/a', self.clone.first), self.branch('ci/b', self.clone.second)])
        self.assertEqual(result.returncode, 0)
        self.assertLess(seconds, 2)
        self.assertIn(self.clone.second[:7], result.stdout + result.stderr)
        started = self.started()
        self.assertEqual(len(started), 1, started)
        sha, pgid, pid = started[0].split()
        self.assertEqual(sha, self.clone.second)
        self.assertEqual(pgid.split('=')[1], pid.split('=')[1], 'not in a session of its own')

    def test_hook_skips_deletions_tags_main_and_other_remotes(self):
        zero = '0' * 40
        skipped = [
            f'(delete) {zero} refs/heads/ci/gone {self.clone.first}',
            f'refs/tags/v1 {self.clone.first} refs/tags/v1 {zero}',
            self.branch('main', self.clone.first),
        ]
        result, _ = self.push(skipped)
        self.assertEqual(result.returncode, 0)
        other, _ = self.push([self.branch('ci/x', self.clone.first)], remote='backup')
        self.assertEqual(other.returncode, 0)
        time.sleep(1)
        self.assertEqual(self.started(wait=False), [])


FAKE_XCODEBUILD = r'''#!/bin/bash
echo $$ >> "$FAKE_DIR/xcodebuild.pids"
echo "Building"
sleep 60
'''

FAKE_XCRUN_FOR_TEST_SH = '#!/bin/bash\nexit 0\n'


# The real test.sh, which ci-mac.sh relies on to end when it's stopped rather than go on to its retry.
@unittest.skipUnless(sys.platform == 'darwin', 'test.sh runs on macOS only (BSD stat)')
class TestShSignalTests(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp(prefix='test-sh-')
        self.addCleanup(self.remove)
        os.mkdir(os.path.join(self.dir, 'scripts'))
        for name in ('test.sh', 'xcodebuild-log.py'):
            shutil.copy(os.path.join(ROOT, 'scripts', name), os.path.join(self.dir, 'scripts'))
        self.fakes = os.path.join(self.dir, 'fakes')
        write(os.path.join(self.fakes, 'xcodebuild'), FAKE_XCODEBUILD)
        write(os.path.join(self.fakes, 'xcrun'), FAKE_XCRUN_FOR_TEST_SH)

    def started(self):
        path = os.path.join(self.fakes, 'xcodebuild.pids')
        if not os.path.exists(path):
            return []
        with open(path) as f:
            return [int(pid) for pid in f.read().split()]

    def remove(self):
        for pid in self.started():
            try:
                os.kill(pid, signal.SIGKILL)
            except OSError:
                pass
        shutil.rmtree(self.dir, ignore_errors=True)

    def stopped_by(self, signum):
        env = dict(os.environ, PATH=self.fakes + os.pathsep + os.environ['PATH'], FAKE_DIR=self.fakes,
                   SIMPANIN_SIMULATOR='FAKE')
        env.pop('GITHUB_ACTIONS', None)
        run = subprocess.Popen(['scripts/test.sh'], cwd=self.dir, env=env,
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        deadline = time.time() + 20
        while not self.started() and time.time() < deadline:
            time.sleep(0.2)
        self.assertTrue(self.started(), 'xcodebuild never started')
        time.sleep(1)
        run.send_signal(signum)
        try:
            run.wait(timeout=15)
        except subprocess.TimeoutExpired:
            run.kill()
            run.wait()
            self.fail('test.sh went on after the signal')
        time.sleep(1)  # a second try would have started by now
        return run.returncode

    def test_term_ends_it_without_a_second_try(self):
        self.assertEqual(self.stopped_by(signal.SIGTERM), 143)
        self.assertEqual(len(self.started()), 1)
        self.assertFalse(any(alive(pid) for pid in self.started()), 'xcodebuild still running')

    def test_int_ends_it_without_a_second_try(self):
        self.assertEqual(self.stopped_by(signal.SIGINT), 130)
        self.assertEqual(len(self.started()), 1)
        self.assertFalse(any(alive(pid) for pid in self.started()), 'xcodebuild still running')


if __name__ == '__main__':
    unittest.main(verbosity=2)
