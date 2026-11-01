import os
import shutil
import subprocess
import tempfile
import unittest
from contextlib import redirect_stdout
from io import StringIO

from engine import conformance


SPEC = """# x — y

## Summary

Mentions **B9** here, which must not count.

## Behavior

1. **B1** — first
2. **B2** — second
3. **B1** — duplicate id is reported once

## Open Questions

- [ ] **B7** not a behavior
"""


class TestBehaviorIds(unittest.TestCase):
    def test_ids_come_only_from_behavior_section(self):
        self.assertEqual(conformance.behavior_ids(SPEC), ["B1", "B2"])

    def test_spec_without_ids_is_empty(self):
        self.assertEqual(conformance.behavior_ids("## Behavior\n\n1. plain\n"), [])


class TestTags(unittest.TestCase):
    def test_single_and_multiple_tags(self):
        lines = ["// spec: B1", '@DisplayName("spec: B2, B4 - does it")', "no tag B5"]
        self.assertEqual(conformance.tags_in(lines), {"B1", "B2", "B4"})

    def test_uncovered_keeps_spec_order(self):
        self.assertEqual(conformance.uncovered(["B1", "B2", "B3"], {"B2"}), ["B1", "B3"])


class TestAddedLines(unittest.TestCase):
    def test_only_added_lines_are_collected(self):
        diff = (
            "diff --git a/t/test_a.py b/t/test_a.py\n"
            "--- a/t/test_a.py\n"
            "+++ b/t/test_a.py\n"
            "@@ -1 +1,2 @@\n"
            "-# spec: B1\n"
            " # spec: B2\n"
            "+# spec: B3\n"
            "diff --git a/gone.py b/gone.py\n"
            "--- a/gone.py\n"
            "+++ /dev/null\n"
            "-# spec: B4\n"
        )
        self.assertEqual(conformance.added_lines_by_file(diff), {"t/test_a.py": ["# spec: B3"]})


class TestIsTestFile(unittest.TestCase):
    def test_generic_patterns(self):
        for path in ("lib/tests/test_x.py", "pkg/x_test.go", "src/A.test.ts",
                     "src/A.spec.tsx", "test/helpers.js", "src/__tests__/a.js"):
            self.assertTrue(conformance.is_test_file(path, "unknown"), path)

    def test_production_files_are_not_tests(self):
        for path in ("engine/conformance.py", "src/App.tsx", "README.md"):
            self.assertFalse(conformance.is_test_file(path, "unknown"), path)

    def test_java_convention_reused(self):
        self.assertTrue(conformance.is_test_file(
            "svc/src/test/java/com/acme/FooServiceTest.java", "java"))


def _git(cwd, *args):
    subprocess.check_call(["git"] + list(args), cwd=cwd,
                          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


class TestCheckEndToEnd(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.old_cwd = os.getcwd()
        _git(self.tmp, "init", "-q", "-b", "main")
        _git(self.tmp, "config", "user.email", "t@t")
        _git(self.tmp, "config", "user.name", "t")
        os.makedirs(os.path.join(self.tmp, "tests"))
        # A pre-existing test already tagged B1 by an older feature.
        self._write("tests/test_old.py", "# spec: B1\n")
        _git(self.tmp, "add", ".")
        _git(self.tmp, "commit", "-q", "-m", "base")
        _git(self.tmp, "checkout", "-q", "-b", "feature/x")
        os.makedirs(os.path.join(self.tmp, ".specwork", "_spec"))
        os.makedirs(os.path.join(self.tmp, ".specwork", "_state"))
        self._write(".specwork/_state/x-state.json", '{"base_branch": "main"}')
        os.chdir(self.tmp)

    def tearDown(self):
        os.chdir(self.old_cwd)
        shutil.rmtree(self.tmp)

    def _write(self, rel, text):
        with open(os.path.join(self.tmp, rel), "w") as f:
            f.write(text)

    def _run(self):
        out = StringIO()
        with redirect_stdout(out):
            code = conformance.check("x")
        return code, out.getvalue()

    def test_reports_uncovered_ids_and_exits_zero(self):
        self._write(".specwork/_spec/x-spec.md", "## Behavior\n\n1. **B1** — a\n2. **B2** — b\n")
        self._write("tests/test_new.py", "# spec: B2\n")  # untracked file counts
        code, out = self._run()
        self.assertEqual(code, 0)
        # The old, unchanged B1 tag does not count; the new B2 tag does.
        self.assertTrue(out.rstrip().endswith("`: B1"), out)

    def test_committed_branch_tags_count(self):
        self._write(".specwork/_spec/x-spec.md", "## Behavior\n\n1. **B1** — a\n")
        self._write("tests/test_old.py", "# spec: B1\n# spec: B1 again\n")
        _git(self.tmp, "commit", "-q", "-am", "feature work")
        code, out = self._run()
        self.assertEqual(code, 0)
        self.assertIn("✓", out)

    def test_spec_without_ids_is_silent(self):
        self._write(".specwork/_spec/x-spec.md", "## Behavior\n\n1. legacy behavior\n")
        self.assertEqual(self._run(), (0, ""))

    def test_missing_spec_is_silent(self):
        self.assertEqual(self._run(), (0, ""))


if __name__ == "__main__":
    unittest.main()
