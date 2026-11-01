"""Integration tests for open-sdd shell command scripts.

Each test class runs an actual shell script (start.sh, auto.sh) via subprocess
inside a temporary git repository. Tests focus on error paths that don't
require a real Jira instance or network access.
"""
import json
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


# ---------------------------------------------------------------------------
# f-close — durable-rule promotion
# ---------------------------------------------------------------------------

class TestClosePromotion(TmpGitRepo):
    SPEC = (
        "# x — y\n\n## Behavior\n\n1. **B1** — a\n\n"
        "## Safe Constraints\n\n### Safe\n\n- Leads are idempotent per applicationId.\n\n"
        "## Open Questions\n\n- [x] **#1** Retry? — resolved: at most 3 times\n"
    )

    def setUp(self):
        super().setUp()
        Path(".gitignore").write_text(".specwork/\n.opensdd/\n")
        subprocess.run(["git", "add", ".gitignore"], check=True)
        subprocess.run(["git", "commit", "-q", "-m", "ignore"], check=True)
        subprocess.run(["git", "checkout", "-q", "-b", "feature/x"], check=True)
        state = Path(".specwork/_state")
        state.mkdir(parents=True)
        (state / "x-state.json").write_text(
            '{"id": "x", "slug": "x", "branch": "feature/x", "base_branch": "main"}\n')
        spec = Path(".specwork/_spec")
        spec.mkdir(parents=True)
        (spec / "x-spec.md").write_text(self.SPEC)

    def _run_close(self, args, stdin="s\n"):
        env = os.environ.copy()
        env.pop("SDD_NON_INTERACTIVE", None)
        return subprocess.run(
            ["bash", str(COMMANDS_DIR / "close.sh")] + args,
            capture_output=True, text=True, cwd=str(self.repo), env=env,
            input=stdin, timeout=15,
        )

    def test_first_pass_prints_candidates_and_deletes_nothing(self):
        r = self._run_close([])
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("PROMOTE DURABLE RULES", r.stdout)
        self.assertIn("Leads are idempotent per applicationId.", r.stdout)
        self.assertIn("resolved: at most 3 times", r.stdout)
        self.assertTrue(Path(".specwork/_spec/x-spec.md").exists())

    def test_rejected_target_closes_nothing(self):
        r = self._run_close(["--promote", '[{"file": ".opensdd/service-rules.md", "section": "S", "rule": "r"}]'])
        self.assertNotEqual(r.returncode, 0)
        self.assertTrue(Path(".specwork/_spec/x-spec.md").exists())

    def test_approved_rules_are_written_and_pipeline_closed(self):
        r = self._run_close(["--promote", '[{"section": "Business Invariants", "rule": "Leads are idempotent per applicationId."}]'])
        self.assertEqual(r.returncode, 0, r.stderr)
        rules = Path(".claude/rules/service-rules.md").read_text()
        self.assertIn("- Leads are idempotent per applicationId. _(from spec x, ", rules)
        self.assertFalse(Path(".specwork").exists())

    def test_no_promote_closes_without_writing_rules(self):
        r = self._run_close(["--no-promote"])
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertFalse(Path(".claude/rules").exists())
        self.assertFalse(Path(".specwork").exists())


# ---------------------------------------------------------------------------
# f-spec --tier — forced triage tier in refine mode
# ---------------------------------------------------------------------------

class TestSpecTier(TmpGitRepo):
    SPEC = ("# x — y\n\n## Behavior\n\n1. **B1** — It does not publish to Kafka.\n\n"
            "## Implementation Context\n\n- MenuController\n\n## Open Questions\n\n")

    def setUp(self):
        super().setUp()
        subprocess.run(["git", "checkout", "-q", "-b", "feature/x"], check=True)
        state = Path(".specwork/_state")
        state.mkdir(parents=True)
        (state / "x-state.json").write_text(
            '{"id": "x", "slug": "x", "branch": "feature/x", "ticket_type": "high-risk"}\n')
        for name in ("x-rules.json", "x-implementation-cache.json"):
            (state / name).write_text("{}\n")
        spec = Path(".specwork/_spec")
        spec.mkdir(parents=True)
        (spec / "x-spec.md").write_text(self.SPEC)
        (spec / "x-source.md").write_text("# x\n")

    def _run_spec(self, args):
        env = os.environ.copy()
        env.pop("SDD_NON_INTERACTIVE", None)
        return subprocess.run(["bash", str(COMMANDS_DIR / "spec.sh")] + args,
                              capture_output=True, text=True, cwd=str(self.repo), env=env, timeout=15)

    def test_tier_only_forces_tier_and_leaves_spec_untouched(self):
        r = self._run_spec(["--tier", "focused", "read-only"])
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("Tier forced", r.stdout)
        data = json.loads(Path(".specwork/_state/x-path.json").read_text())
        self.assertEqual(data["override"]["tier"], "focused")
        self.assertEqual(Path(".specwork/_spec/x-spec.md").read_text(), self.SPEC)

    def test_tier_without_reason_is_rejected(self):
        r = self._run_spec(["--tier", "focused"])
        self.assertNotEqual(r.returncode, 0)
        self.assertFalse(Path(".specwork/_state/x-path.json").exists())
