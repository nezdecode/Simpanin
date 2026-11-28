#!/usr/bin/env python3
# Tests the private-files check in scripts/hooks/pre-commit and in scripts/ci-checks.sh's refused_files,
# which keep the notes, the agent settings and the code graph out of the public repository. A worktree
# links docs and .claude instead of holding folders, and git lists a link by its bare name, so both forms
# are tried. pre-commit runs in a throwaway repository; refused_files is read out of ci-checks.sh and run
# on its own. Run by scripts/ci-checks.sh; by hand with:
#   python3 scripts/test-private-files.py

import os
import subprocess
import tempfile
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PRE_COMMIT = os.path.join(ROOT, 'scripts', 'hooks', 'pre-commit')
CI_CHECKS = os.path.join(ROOT, 'scripts', 'ci-checks.sh')

PRIVATE = ['docs', 'docs/made-up-note.md', '.claude', '.claude/settings.json', 'graphify-out/graph.json', 'CLAUDE.md',
           'AGENTS.md']
# Names that only start like a private one, so the pattern can't refuse too much.
PUBLIC = ['README.md', 'docsets.md', '.claudeignore', 'Simpanin/docs/notes.md', 'Simpanin/CLAUDE.md']
LINKS = ['docs', '.claude']


def pre_commit(path, link):
    """Stages path alone in a new repository, as a link or a file, and runs the real pre-commit there."""
    with tempfile.TemporaryDirectory() as repo:
        subprocess.run(['git', 'init', '-q', repo], check=True)
        # pre-commit runs commit-checks.py after the private check; a stand-in that passes lets a public path
        # reach exit 0, so a hook that refused everything would fail the public cases.
        os.makedirs(os.path.join(repo, 'scripts'))
        with open(os.path.join(repo, 'scripts', 'commit-checks.py'), 'w') as file:
            file.write('')
        full = os.path.join(repo, path)
        os.makedirs(os.path.dirname(full), exist_ok=True)
        if link:
            os.symlink('/nonexistent', full)
        else:
            with open(full, 'w') as file:
                file.write('made up\n')
        subprocess.run(['git', 'add', '-f', path], cwd=repo, check=True)
        return subprocess.run(['sh', PRE_COMMIT], cwd=repo, capture_output=True, text=True)


def assert_refused(test, result):
    test.assertEqual(result.returncode, 1, result.stderr)
    test.assertIn('refusing to commit private files', result.stderr)


def ci_checks_refuses(path):
    """Runs ci-checks.sh's own refused_files on one path, the way it's called for a commit."""
    with open(CI_CHECKS) as file:
        lines = file.read().splitlines()
    start = lines.index('refused_files() {')
    function = '\n'.join(lines[start:lines.index('}', start) + 1])
    script = f'set -euo pipefail\nfailed=0\n{function}\nrefused_files "$1" test 2>/dev/null\necho "$failed"'
    result = subprocess.run(['bash', '-c', script, 'bash', path], capture_output=True, text=True, check=True)
    return result.stdout.strip() == '1'


class PrivateFilesTests(unittest.TestCase):
    def test_pre_commit_refuses_each_private_path(self):
        for path in PRIVATE:
            with self.subTest(path=path):
                assert_refused(self, pre_commit(path, link=False))

    def test_pre_commit_refuses_a_staged_link(self):
        for path in LINKS:
            with self.subTest(path=path):
                assert_refused(self, pre_commit(path, link=True))

    def test_pre_commit_lets_public_paths_through(self):
        for path in PUBLIC:
            with self.subTest(path=path):
                result = pre_commit(path, link=False)
                self.assertEqual(result.returncode, 0, result.stderr)

    def test_ci_checks_refuses_each_private_path(self):
        for path in PRIVATE:
            with self.subTest(path=path):
                self.assertTrue(ci_checks_refuses(path))

    def test_ci_checks_lets_public_paths_through(self):
        for path in PUBLIC:
            with self.subTest(path=path):
                self.assertFalse(ci_checks_refuses(path))


if __name__ == '__main__':
    unittest.main()
