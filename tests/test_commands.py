"""Integration tests for open-sdd shell command scripts.

Each test class runs an actual shell script (start.sh, auto.sh) via subprocess
inside a temporary git repository. Tests focus on error paths that don't
require a real Jira instance or network access.
"""
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).parent.parent
COMMANDS_DIR = REPO_ROOT / "commands"


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _init_git_repo(path: Path):
    """Create a minimal git repo with one empty commit on main."""
    for cmd in [
        ["git", "init", str(path)],
        ["git", "-C", str(path), "config", "user.email", "test@opensdd.test"],
        ["git", "-C", str(path), "config", "user.name", "Test"],
        ["git", "-C", str(path), "commit", "--allow-empty", "-m", "init"],
    ]:
        subprocess.run(cmd, check=True, capture_output=True)


class TmpGitRepo(unittest.TestCase):
    """Base: provides a temporary git repo; cwd is set inside it for each test."""

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.repo = Path(self._tmp.name)
        self._cwd = os.getcwd()
        os.chdir(self.repo)
        self.addCleanup(self._tmp.cleanup)
        self.addCleanup(lambda: os.chdir(self._cwd))
        _init_git_repo(self.repo)

    def _env_no_jira(self):
        """os.environ copy with all Jira variables removed."""
        env = os.environ.copy()
        for k in ("JIRA_BASE_URL", "JIRA_URL", "JIRA_TOKEN", "JIRA_USER", "JIRA_AUTH_MODE"):
            env.pop(k, None)
        return env

    def _env_bad_jira(self):
        """Jira vars set but pointing to a port that refuses connections instantly."""
        env = self._env_no_jira()
        env["JIRA_BASE_URL"] = "http://127.0.0.1:1"
        env["JIRA_TOKEN"] = "fake-token"
        return env

    def _run_start(self, args, env=None, timeout=15):
        return subprocess.run(
            ["bash", str(COMMANDS_DIR / "start.sh")] + args,
            capture_output=True, text=True,
            cwd=str(self.repo),
            env=env if env is not None else os.environ.copy(),
            timeout=timeout,
        )

    def _run_auto(self, args, env=None, timeout=15):
        return subprocess.run(
            ["bash", str(COMMANDS_DIR / "auto.sh")] + args,
            capture_output=True, text=True,
            cwd=str(self.repo),
            env=env if env is not None else os.environ.copy(),
            timeout=timeout,
        )


# ---------------------------------------------------------------------------
# f-start — no arguments
# ---------------------------------------------------------------------------

class TestStartNoArgs(TmpGitRepo):
    def test_exits_nonzero(self):
        r = self._run_start([])
        self.assertNotEqual(r.returncode, 0)

    def test_prints_usage(self):
        r = self._run_start([])
        self.assertIn("Usage", r.stdout + r.stderr)

    def test_no_specwork_created(self):
        self._run_start([])
        self.assertFalse((self.repo / ".specwork").exists())


# ---------------------------------------------------------------------------
# f-start — Jira ticket key but Jira not configured
# ---------------------------------------------------------------------------

class TestStartJiraNotConfigured(TmpGitRepo):
    def test_exits_nonzero(self):
        r = self._run_start(["MYYES-123"], env=self._env_no_jira())
        self.assertNotEqual(r.returncode, 0)

    def test_error_mentions_jira_not_configured(self):
        r = self._run_start(["MYYES-123"], env=self._env_no_jira())
        self.assertIn("Jira is not configured", r.stderr)

    def test_no_specwork_artifacts_created(self):
        self._run_start(["MYYES-123"], env=self._env_no_jira())
        self.assertFalse((self.repo / ".specwork").exists())

    def test_error_lists_required_env_vars(self):
        r = self._run_start(["MYYES-123"], env=self._env_no_jira())
        self.assertIn("JIRA_BASE_URL", r.stderr)
        self.assertIn("JIRA_TOKEN", r.stderr)


# ---------------------------------------------------------------------------
# f-start — Jira ticket key but Jira fetch fails (configured, unreachable)
# ---------------------------------------------------------------------------

class TestStartJiraFetchFails(TmpGitRepo):
    def test_exits_nonzero(self):
        r = self._run_start(["MYYES-123"], env=self._env_bad_jira(), timeout=10)
        self.assertNotEqual(r.returncode, 0)

    def test_error_mentions_jira_ticket(self):
        r = self._run_start(["MYYES-123"], env=self._env_bad_jira(), timeout=10)
        combined = r.stdout + r.stderr
        self.assertIn("MYYES-123", combined)

    def test_no_specwork_artifacts_created(self):
        self._run_start(["MYYES-123"], env=self._env_bad_jira(), timeout=10)
        self.assertFalse((self.repo / ".specwork").exists())


# ---------------------------------------------------------------------------
# f-start — dirty working tree on main blocks initialization
# ---------------------------------------------------------------------------

class TestStartDirtyTreeOnMain(TmpGitRepo):
    def setUp(self):
        super().setUp()
        (self.repo / "dirty.txt").write_text("uncommitted change")

    def test_rejects_on_main_with_dirty_tree(self):
        r = self._run_start(["fix-something", "--keep"], env=self._env_no_jira())
        self.assertNotEqual(r.returncode, 0)

    def test_error_mentions_working_tree(self):
        r = self._run_start(["fix-something", "--keep"], env=self._env_no_jira())
        self.assertIn("changes", r.stdout + r.stderr)

    def test_no_specwork_created(self):
        self._run_start(["fix-something", "--keep"], env=self._env_no_jira())
        self.assertFalse((self.repo / ".specwork").exists())


# ---------------------------------------------------------------------------
# f-start — freetext input, success path
# ---------------------------------------------------------------------------

class TestStartFreetextSuccess(TmpGitRepo):
    def setUp(self):
        super().setUp()
        # Use a feature branch so the clean-tree gate on main is not triggered.
        subprocess.run(
            ["git", "-C", str(self.repo), "checkout", "-b", "feature/test"],
            check=True, capture_output=True,
        )

    def test_exits_zero(self):
        r = self._run_start(["fix duplicate leads", "--keep"], env=self._env_no_jira())
        self.assertEqual(r.returncode, 0, msg=r.stderr)

    def test_creates_state_json(self):
        self._run_start(["fix duplicate leads", "--keep"], env=self._env_no_jira())
        states = list((self.repo / ".specwork" / "_state").glob("*-state.json"))
        self.assertTrue(states, "No state.json created")

    def test_creates_source_md(self):
        self._run_start(["fix duplicate leads", "--keep"], env=self._env_no_jira())
        sources = list((self.repo / ".specwork" / "_spec").glob("*-source.md"))
        self.assertTrue(sources, "No source.md created")

    def test_source_body_contains_description(self):
        self._run_start(["fix duplicate leads", "--keep"], env=self._env_no_jira())
        source = next((self.repo / ".specwork" / "_spec").glob("*-source.md")).read_text()
        self.assertIn("fix duplicate leads", source)

    def test_specwork_added_to_gitignore(self):
        self._run_start(["fix something", "--keep"], env=self._env_no_jira())
        self.assertIn(".specwork", (self.repo / ".gitignore").read_text())

    def test_idempotent_gitignore(self):
        self._run_start(["fix something", "--keep"], env=self._env_no_jira())
        self._run_start(["fix something else", "--keep"], env=self._env_no_jira())
        gitignore = (self.repo / ".gitignore").read_text()
        self.assertEqual(gitignore.count(".specwork/"), 1)


# ---------------------------------------------------------------------------
# f-auto — no arguments
# ---------------------------------------------------------------------------

class TestAutoNoArgs(unittest.TestCase):
    def test_exits_nonzero(self):
        r = subprocess.run(
            ["bash", str(COMMANDS_DIR / "auto.sh")],
            capture_output=True, text=True, timeout=10,
        )
        self.assertNotEqual(r.returncode, 0)

    def test_prints_usage(self):
        r = subprocess.run(
            ["bash", str(COMMANDS_DIR / "auto.sh")],
            capture_output=True, text=True, timeout=10,
        )
        self.assertIn("Usage", r.stdout + r.stderr)


# ---------------------------------------------------------------------------
# f-auto — Jira ticket key but Jira not configured
# ---------------------------------------------------------------------------

class TestAutoJiraNotConfigured(TmpGitRepo):
    def test_exits_nonzero(self):
        r = self._run_auto(["MYYES-123", "--choose", "A"], env=self._env_no_jira())
        self.assertNotEqual(r.returncode, 0)

    def test_error_mentions_jira(self):
        r = self._run_auto(["MYYES-123", "--choose", "A"], env=self._env_no_jira())
        combined = r.stdout + r.stderr
        self.assertIn("Jira is not configured", combined)

    def test_no_specwork_artifacts_created(self):
        self._run_auto(["MYYES-123", "--choose", "A"], env=self._env_no_jira())
        self.assertFalse((self.repo / ".specwork").exists())


if __name__ == "__main__":
    unittest.main()
