import json
import os
import shutil
import subprocess
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from io import StringIO

from engine import audit
from engine.cli import cmd_audit_required, cmd_audit_record


def _git(cwd, *args):
    subprocess.check_call(["git"] + list(args), cwd=cwd,
                          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


class TestAudit(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.old_cwd = os.getcwd()
        _git(self.tmp, "init", "-q", "-b", "main")
        _git(self.tmp, "config", "user.email", "t@t")
        _git(self.tmp, "config", "user.name", "t")
        self._write("app.py", "x = 1\n")
        _git(self.tmp, "add", ".")
        _git(self.tmp, "commit", "-q", "-m", "base")
        _git(self.tmp, "checkout", "-q", "-b", "feature/x")
        os.makedirs(os.path.join(self.tmp, ".specwork", "_state"))
        self._write(".specwork/_state/x-state.json", json.dumps({"base_branch": "main"}))
        os.chdir(self.tmp)

    def tearDown(self):
        os.chdir(self.old_cwd)
        shutil.rmtree(self.tmp)

    def _write(self, rel, text):
        with open(os.path.join(self.tmp, rel), "w") as f:
            f.write(text)

    def _tier(self, ticket_type):
        self._write(".specwork/_state/x-path.json", json.dumps({"ticket_type": ticket_type}))

    def _stage(self, text):
        self._write("app.py", text)
        _git(self.tmp, "add", "app.py")

    def test_high_risk_without_receipt_requires_audit(self):
        self._tier("high-risk")
        self._stage("x = 2\n")
        self.assertTrue(audit.audit_required("x"))

    def test_other_tiers_never_require_audit(self):
        self._stage("x = 2\n")
        for tier in ("trivial", "focused", "standard"):
            self._tier(tier)
            self.assertFalse(audit.audit_required("x"), tier)

    def test_missing_or_corrupt_path_json_fails_open(self):
        self.assertFalse(audit.audit_required("x"))
        self._write(".specwork/_state/x-path.json", "{not json")
        self.assertFalse(audit.audit_required("x"))

    def test_fingerprint_tracks_staged_content_only(self):
        self._stage("x = 2\n")
        first = audit.diff_fingerprint("x")
        self._write("app.py", "x = 3\n")  # unstaged edit: not part of the commit
        self.assertEqual(audit.diff_fingerprint("x"), first)
        _git(self.tmp, "add", "app.py")
        self.assertNotEqual(audit.diff_fingerprint("x"), first)

    def test_fingerprint_covers_committed_branch_work(self):
        self._stage("x = 2\n")
        staged = audit.diff_fingerprint("x")
        _git(self.tmp, "commit", "-q", "-m", "wip")
        # Same branch content, now committed: still the same diff vs merge-base.
        self.assertEqual(audit.diff_fingerprint("x"), staged)

    def test_record_writes_receipt(self):
        self._stage("x = 2\n")
        fp = audit.record("x", "pass with warnings")
        with open(audit.receipt_file("x")) as f:
            data = json.load(f)
        self.assertEqual(data["fingerprint"], fp)
        self.assertEqual(data["verdict"], "PASS WITH WARNINGS")
        self.assertIn("recorded_at", data)

    def test_unknown_verdict_rejected_without_write(self):
        with self.assertRaises(ValueError):
            audit.record("x", "MAYBE")
        self.assertFalse(os.path.exists(audit.receipt_file("x")))
        with redirect_stderr(StringIO()):
            self.assertEqual(cmd_audit_record(["x", "MAYBE"]), 2)

    def test_matching_receipt_skips_second_review(self):
        self._tier("high-risk")
        self._stage("x = 2\n")
        audit.record("x", "FAIL")
        self.assertFalse(audit.audit_required("x"))
        with redirect_stdout(StringIO()):
            self.assertEqual(cmd_audit_required(["x"]), 0)
        self._stage("x = 9\n")  # diff changed → review again
        self.assertTrue(audit.audit_required("x"))
        with redirect_stdout(StringIO()):
            self.assertEqual(cmd_audit_required(["x"]), 1)


if __name__ == "__main__":
    unittest.main()
