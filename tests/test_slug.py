"""Slug derivation: one helper (engine/slug.py), every caller agrees."""
import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

from engine.gates import resolve_slug
from engine.slug import normalize, slug_from_branch

REPO_ROOT = Path(__file__).resolve().parent.parent

CASES = {
    "feature/PROJ-123": "proj-123",
    "feature/IR-70.1": "ir-70-1",
    "feature/my_slug": "my-slug",
    "bugfix/ABC-9-fix-null": "abc-9-fix-null",
    "release/2.0": "2-0",
    "chore/foo": "chore-foo",
    "feature/a/b": "a-b",
    "main": "main",
}


class TestSlugFromBranch(unittest.TestCase):
    def test_cases(self):
        for branch, slug in CASES.items():
            self.assertEqual(slug_from_branch(branch), slug, branch)

    def test_normalize_collapses_and_trims(self):
        self.assertEqual(normalize("  --Add  email__validation!! "), "add-email-validation")


class TestCallersAgree(unittest.TestCase):
    """Python resolve_slug, lib/gates.sh resolve_slug and the CLI derive the same slug."""

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self._old = os.getcwd()
        os.chdir(self._tmp.name)
        for cmd in (["git", "init", "-q"], ["git", "config", "user.email", "t@t"],
                    ["git", "config", "user.name", "t"], ["git", "commit", "-q", "--allow-empty", "-m", "i"]):
            subprocess.run(cmd, check=True)

    def tearDown(self):
        os.chdir(self._old)
        self._tmp.cleanup()

    def _cli(self, *args):
        env = {**os.environ, "PYTHONPATH": str(REPO_ROOT)}
        return subprocess.run(["python3", "-m", "engine.cli", *args], capture_output=True, text=True, env=env)

    def _gates_sh(self):
        script = f'source "{REPO_ROOT}/lib/gates.sh"; resolve_slug'
        return subprocess.run(["bash", "-c", script], capture_output=True, text=True).stdout

    def test_all_callers_match_for_every_case(self):
        for branch, slug in CASES.items():
            if branch == "main":
                continue
            subprocess.run(["git", "checkout", "-q", "-B", branch], check=True)
            self.assertEqual(resolve_slug(), slug, branch)
            self.assertEqual(self._gates_sh(), slug, branch)
            self.assertEqual(self._cli("slug").stdout.strip(), slug, branch)
            self.assertEqual(json.loads(self._cli("derive-branch").stdout)["slug"], slug, branch)

    def test_state_file_still_wins_over_derivation(self):
        subprocess.run(["git", "checkout", "-q", "-b", "chore/foo"], check=True)
        Path(".specwork/_state").mkdir(parents=True)
        Path(".specwork/_state/legacy-state.json").write_text(
            json.dumps({"id": "legacy", "slug": "legacy", "branch": "chore/foo"}))
        self.assertEqual(resolve_slug(), "legacy")
        self.assertEqual(self._gates_sh(), "legacy")


if __name__ == "__main__":
    unittest.main()
