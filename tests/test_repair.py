import json
import os
import shutil
import subprocess
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from io import StringIO

from engine import repair
from engine.cli import DISPATCH


def _git(cwd, *args):
    subprocess.check_call(["git"] + list(args), cwd=cwd,
                          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def _is_test(path):
    return path.startswith("tests/")


def _change(status="M", removed=(), added=()):
    return {"status": status, "removed": list(removed), "added": list(added)}


class TestParsers(unittest.TestCase):
    def test_name_status(self):
        text = "M\0src/a.py\0D\0tests/test_b.py\0A\0path with b/ inside.py\0"
        self.assertEqual(repair.parse_name_status(text),
                         {"src/a.py": "M", "tests/test_b.py": "D", "path with b/ inside.py": "A"})

    def test_hunks_skip_headers(self):
        diff = ("diff --git a/q.sql b/q.sql\n--- a/q.sql\n+++ b/q.sql\n"
                "@@ -1 +1 @@\n--- a sql comment\n+++ another\n")
        self.assertEqual(repair.parse_hunks(diff), (["-- a sql comment"], ["++ another"]))


class TestSkipMarkers(unittest.TestCase):
    def test_detects_markers(self):
        for line in ("@Disabled", "@Ignore", "@pytest.mark.skip(reason='x')", "@pytest.mark.skipif(True, reason='x')",
                     "@pytest.mark.xfail", "@unittest.skip('x')", "@unittest.expectedFailure", "pytest.skip('x')",
                     "pytest.importorskip('numpy')", "raise unittest.SkipTest('x')", "self.skipTest('x')",
                     "Assume.assumeTrue(false);", "assumeFalse(flag);", "assumeThat(x, is(1));",
                     "it.skip('x', () => {})", "describe.only('x', () => {})", "test.todo('x')",
                     "xit('x', () => {})", "fdescribe('x')", "t.Skip(\"later\")", "t.SkipNow()", "#[ignore]"):
            self.assertEqual(len(repair.skip_markers([line])), 1, line)

    def test_ignores_ordinary_lines(self):
        self.assertEqual(repair.skip_markers(["assert skipped == 0", "def test_exit():", "it('x')",
                                              "assumed = True"]), [])


class TestViolations(unittest.TestCase):
    def test_clean_production_fix(self):
        changes = {"src/app.py": _change(removed=["x = 1"], added=["x = 2"])}
        self.assertEqual(repair.violations(changes, _is_test), [])

    def test_check_script(self):
        found = repair.violations({"commands/check.sh": _change(added=["exit 0"])}, _is_test)
        self.assertIn("commands/check.sh", found[0])

    def test_test_configs_reject_any_change(self):
        for path in ("pytest.ini", "conftest.py", "tests/conftest.py", "jest.config.js", ".mocharc.yml",
                     "vitest.config.ts"):
            found = repair.violations({path: _change(status="A", added=["[pytest]"])}, _is_test)
            self.assertEqual(len(found), 1, path)
            self.assertIn("test-runner config", found[0])

    def test_build_file_exclusions(self):
        for line in ('addopts = -k "not broken"', '"testPathIgnorePatterns": ["pricing"]',
                     "<exclude>**/PricingTest.java</exclude>", "  exclude '**/PricingTest*'",
                     "<skipTests>true</skipTests>", "--deselect tests/test_p.py::test_x",
                     'addopts = -m "not slow"'):
            found = repair.violations({"pyproject.toml": _change(added=[line])}, _is_test)
            self.assertEqual(len(found), 1, line)

    def test_build_file_dependency_bump_is_fine(self):
        changes = {"package.json": _change(removed=['"lodash": "4.17.20"'], added=['"lodash": "4.17.21"'])}
        self.assertEqual(repair.violations(changes, _is_test), [])

    def test_existing_test_modified(self):
        found = repair.violations({"tests/test_a.py": _change(removed=["assert x == 1"], added=["assert x == 2"])},
                                  _is_test)
        self.assertIn("existing line", found[0])

    def test_existing_test_insertions_allowed(self):
        self.assertEqual(repair.violations({"tests/test_a.py": _change(added=["    assert y"])}, _is_test), [])

    def test_existing_test_deleted(self):
        found = repair.violations({"tests/test_a.py": _change(status="D", removed=["x"])}, _is_test)
        self.assertIn("deleted", found[0])

    def test_skip_in_new_test(self):
        found = repair.violations({"tests/test_new.py": _change(status="A", added=["xit('x')"])}, _is_test)
        self.assertIn("skip marker", found[0])

    def test_non_test_file_skip_is_ignored(self):
        self.assertEqual(repair.violations({"src/a.py": _change(status="A", added=["@Disabled"])}, _is_test), [])


class TestStateHelpers(unittest.TestCase):
    def test_state_name_is_per_branch_and_collision_free(self):
        a, b = repair.state_name("feature/x"), repair.state_name("feature_x")
        self.assertTrue(a.startswith(repair.STATE_PREFIX + "-feature_x-"))
        self.assertNotEqual(a, b)
        self.assertRegex(repair.state_name("weird branch!"), r"^[A-Za-z0-9._-]+\.json$")

    def test_counts_attempt_only_on_changed_content(self):
        self.assertFalse(repair.counts_attempt({"checked_tree": "t1"}, "t1"))
        self.assertTrue(repair.counts_attempt({"checked_tree": "t1"}, "t2"))
        self.assertTrue(repair.counts_attempt({}, "t1"))

    def test_uncommitted_ignores_preexisting_untracked(self):
        self.assertEqual(repair.uncommitted(["app.py"], [".DS_Store", "tests/test_new.py"], [".DS_Store"]),
                         ["app.py", "tests/test_new.py"])
        self.assertEqual(repair.uncommitted([], [".DS_Store"], [".DS_Store"]), [])


class TestNextStep(unittest.TestCase):
    def test_green_tree_skips_check(self):
        self.assertEqual(repair.next_step({"attempts": 3, "green_tree": "t1"}, "t1"), "SKIP_CHECK")

    def test_exhausted(self):
        self.assertEqual(repair.next_step({"attempts": 3}, "t1"), "EXHAUSTED")

    def test_run_check(self):
        self.assertEqual(repair.next_step({"attempts": 2, "green_tree": "t0"}, "t1"), "RUN_CHECK")


class RepoCase(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.old_cwd = os.getcwd()
        _git(self.tmp, "init", "-q", "-b", "main")
        _git(self.tmp, "config", "user.email", "t@t")
        _git(self.tmp, "config", "user.name", "t")
        self._write(".gitignore", ".specwork/\n")
        self._write("commands/check.sh", "python3 -m pytest\n")
        self._write("app.py", "x = 1\n")
        self._write("tests/test_app.py", "def test_x():\n    assert x == 1\n")
        _git(self.tmp, "add", ".")
        _git(self.tmp, "commit", "-q", "-m", "base")
        os.chdir(self.tmp)
        self.base = subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip()

    def tearDown(self):
        os.chdir(self.old_cwd)
        shutil.rmtree(self.tmp)

    def _write(self, rel, text):
        path = os.path.join(self.tmp, rel)
        os.makedirs(os.path.dirname(path) or self.tmp, exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            f.write(text)

    def _run(self, *args):
        out, err = StringIO(), StringIO()
        with redirect_stdout(out), redirect_stderr(err):
            rc = DISPATCH["repair-" + args[0]](list(args[1:]))
        return rc, out.getvalue() + err.getvalue()


class TestGuardCli(RepoCase):
    def test_clean_fix_passes(self):
        self._write("app.py", "x = 2\n")
        self.assertEqual(self._run("guard", self.base)[0], 0)

    def test_edited_existing_test_fails(self):
        self._write("tests/test_app.py", "def test_x():\n    assert True\n")
        rc, out = self._run("guard", self.base)
        self.assertEqual(rc, 1)
        self.assertIn("tests/test_app.py", out)

    def test_untracked_pytest_ini_fails(self):
        self._write("pytest.ini", '[pytest]\naddopts = -k "not broken"\n')
        rc, out = self._run("guard", self.base)
        self.assertEqual(rc, 1)
        self.assertIn("pytest.ini", out)

    def test_committed_violation_still_caught(self):
        os.remove(os.path.join(self.tmp, "tests/test_app.py"))
        _git(self.tmp, "commit", "-q", "-am", "drop test")
        rc, out = self._run("guard", self.base)
        self.assertEqual(rc, 1)
        self.assertIn("deleted", out)

    def test_bad_ref_and_usage(self):
        self.assertEqual(self._run("guard", "no-such-ref")[0], 2)
        self.assertEqual(self._run("guard")[0], 2)
        self.assertEqual(self._run("red", "extra")[0], 2)


class TestLoop(RepoCase):
    def _state(self):
        return repair.load_state()

    def test_no_loop(self):
        self.assertEqual(self._run("pre"), (0, "NONE\n"))
        self.assertEqual(self._run("green")[0], 0)
        self.assertEqual(self._run("status")[1].strip(), "none")

    def test_state_lives_in_git_dir(self):
        self._run("red")
        path = repair.state_file()
        self.assertTrue(path.is_file())
        self.assertEqual(os.path.basename(os.path.dirname(os.path.abspath(path))), ".git")
        self.assertEqual(subprocess.check_output(["git", "status", "--porcelain"], text=True), "")

    def test_full_cycle_commit_then_skip_recheck(self):
        rc, out = self._run("red")
        self.assertEqual(rc, 0)
        self.assertIn("REPAIR_BASE=" + self.base, out)
        self._write("app.py", "x = 2\n")
        self.assertEqual(self._run("pre"), (0, "RUN_CHECK\n"))
        self.assertEqual(self._state()["attempts"], 1)
        rc, _ = self._run("green")                      # green but uncommitted
        self.assertEqual(rc, 4)
        _git(self.tmp, "commit", "-q", "-am", "fix")
        self.assertEqual(self._run("pre"), (0, "SKIP_CHECK\n"))
        self.assertEqual(self._state()["attempts"], 1)  # the re-run after commit is free
        self.assertEqual(self._run("green")[0], 0)
        self.assertIsNone(self._state())

    def test_cap_of_three(self):
        self._run("red")
        for n in range(1, 4):
            self._write("app.py", "x = {}\n".format(n + 1))
            self.assertEqual(self._run("pre"), (0, "RUN_CHECK\n"))
            rc, _ = self._run("red")
            self.assertEqual(rc, 3 if n == 3 else 0)
        rc, out = self._run("pre")
        self.assertEqual(rc, 1)
        self.assertIn("attempts are used", out)

    def test_violation_blocks_pre_and_green(self):
        self._run("red")
        self._write("commands/check.sh", "exit 0\n")
        self.assertEqual(self._run("pre")[0], 1)
        self.assertEqual(self._run("green")[0], 1)
        self.assertIsNotNone(self._state())

    def test_red_after_green_clears_green_tree(self):
        self._run("red")
        self._write("app.py", "x = 2\n")
        self._run("pre")
        self._run("green")
        self._run("red")
        self.assertNotIn("green_tree", self._state())

    def test_new_untracked_test_file_requires_commit_then_closes(self):
        self._run("red")
        self._write("app.py", "x = 2\n")
        self._write("tests/test_extra.py", "def test_y():\n    assert True\n")
        self.assertEqual(self._run("pre"), (0, "RUN_CHECK\n"))
        rc, out = self._run("green")
        self.assertEqual(rc, 4)
        self.assertIn("tests/test_extra.py", out)
        self.assertIn("git add -- ", out)
        _git(self.tmp, "add", "-A")
        _git(self.tmp, "commit", "-q", "-m", "fix")
        self.assertEqual(self._run("pre"), (0, "SKIP_CHECK\n"))
        self.assertEqual(self._run("green")[0], 0)
        self.assertIsNone(self._state())

    def test_preexisting_untracked_file_does_not_block_green(self):
        self._write(".DS_Store", "junk")
        self._run("red")
        self._write("app.py", "x = 2\n")
        self._run("pre")
        self.assertEqual(self._run("green")[0], 4)
        _git(self.tmp, "commit", "-q", "-am", "fix")
        self._run("pre")
        rc, out = self._run("green")
        self.assertEqual(rc, 0, out)
        self.assertIsNone(self._state())

    def test_preexisting_untracked_test_is_not_guarded(self):
        self._write("tests/test_wip.py", "import pytest\n\n@pytest.mark.skip\ndef test_wip():\n    pass\n")
        self._run("red")
        self._write("app.py", "x = 2\n")
        self.assertEqual(self._run("pre"), (0, "RUN_CHECK\n"))

    def test_rerun_without_changes_does_not_consume_attempts(self):
        self._run("red")
        self._run("pre")
        self._run("red")
        self._run("pre")
        self.assertEqual(self._state()["attempts"], 0)
        self._write("app.py", "x = 2\n")
        self._run("pre")
        self._run("red")
        self._run("pre")
        self.assertEqual(self._state()["attempts"], 1)

    def test_loop_is_per_branch(self):
        self._run("red")
        _git(self.tmp, "checkout", "-q", "-b", "other")
        self.assertEqual(self._run("status")[1].strip(), "none")
        self.assertEqual(self._run("pre"), (0, "NONE\n"))
        _git(self.tmp, "checkout", "-q", "main")
        self.assertIsNotNone(self._state())

    def test_reset(self):
        self._run("red")
        self._run("reset")
        self.assertIsNone(self._state())


if __name__ == "__main__":
    unittest.main()
