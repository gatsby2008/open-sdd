import json
import tempfile
import os
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

from engine.cli import (
    triage,
    cmd_current_step,
    cmd_expected_step,
    cmd_advance_step,
    cmd_set_step,
    cmd_precheck,
    cmd_bump_spec_ts,
)

SPECWORK = Path(".specwork")


class CliTestCase(unittest.TestCase):

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name)
        self._old_cwd = os.getcwd()
        os.chdir(self.root)
        SPECWORK.mkdir(parents=True, exist_ok=True)

    def tearDown(self):
        os.chdir(self._old_cwd)
        self._tmp.cleanup()

    def _write_spec(self, slug, body):
        d = SPECWORK / "_spec"
        d.mkdir(parents=True, exist_ok=True)
        (d / f"{slug}-spec.md").write_text(body, encoding="utf-8")

    def test_triage_trivial(self):
        self._write_spec("rename", """\
# rename — Copy change

## Summary

Rename welcome text.

## Behavior

This is a copy change: replace "Welcome" with "Hello".

## Implementation Context

- Resource bundle

## Expected Change Scope

- **Expected files touched**: 1
- **Expected layers**:
""")
        rc = triage("rename")
        self.assertEqual(rc, 0)
        out = SPECWORK / "_state" / "rename-path.json"
        self.assertTrue(out.exists())
        data = json.loads(out.read_text())
        self.assertEqual(data["ticket_type"], "trivial")
        self.assertNotIn("implement", data["recommended_path"])

    def test_triage_focused(self):
        self._write_spec("validate", """\
# validate — Add input validation

## Summary

Reject empty email.

## Behavior

Service validates email is non-empty.

## Implementation Context

- LoginService

## Expected Change Scope

- **Expected files touched**: 1-2
- **Expected layers**: service
""")
        rc = triage("validate")
        self.assertEqual(rc, 0)
        data = json.loads((SPECWORK / "_state" / "validate-path.json").read_text())
        self.assertEqual(data["ticket_type"], "focused")
        self.assertNotIn("plan", data["recommended_path"])

    def test_triage_standard(self):
        self._write_spec("offers", """\
# offers — Offer listing endpoint

## Summary

New REST endpoint.

## Behavior

Controller receives GET /api/v1/offers. Service queries repository.

## Implementation Context

- OfferController, OfferService, OfferRepository

## Expected Change Scope

- **Expected files touched**: 3-6
- **Expected layers**: controller, service, repository
""")
        rc = triage("offers")
        self.assertEqual(rc, 0)
        data = json.loads((SPECWORK / "_state" / "offers-path.json").read_text())
        self.assertEqual(data["ticket_type"], "standard")
        self.assertIn("plan", data["recommended_path"])
        self.assertNotIn("test-design", data["recommended_path"])

    def test_triage_high_risk_kafka(self):
        self._write_spec("events", """\
# events — Kafka event producer

## Summary

Publish OfferActivated events.

## Behavior

A Kafka consumer receives the state change. Producer publishes with auth token.

## Implementation Context

- KafkaListener, OfferEventProducer

## Expected Change Scope

- **Expected files touched**: 5-8
- **Expected layers**: listener, service, config
""")
        rc = triage("events")
        self.assertEqual(rc, 0)
        data = json.loads((SPECWORK / "_state" / "events-path.json").read_text())
        self.assertEqual(data["ticket_type"], "high-risk")
        self.assertIn("test-design", data["recommended_path"])
        self.assertIn("test-impl", data["recommended_path"])

    def test_triage_high_risk_migration(self):
        self._write_spec("migrate", """\
# migrate — Flyway migration

## Summary

Add consent_given column.

## Behavior

Flyway migration runs on startup. Entity gets new column mapping.

## Implementation Context

- UserRepo, migration files

## Expected Change Scope

- **Expected files touched**: 3-5
- **Expected layers**: repository, service
""")
        rc = triage("migrate")
        self.assertEqual(rc, 0)
        data = json.loads((SPECWORK / "_state" / "migrate-path.json").read_text())
        self.assertEqual(data["ticket_type"], "high-risk")
        self.assertIn("test-design", data["recommended_path"])

    def test_triage_high_risk_auth(self):
        self._write_spec("auth", """\
# auth — Auth token validation

## Summary

Add JWT validation.

## Behavior

Authentication filter validates the token. Returns 401 if invalid.

## Implementation Context

- SecurityConfig, JwtAuthFilter

## Expected Change Scope

- **Expected files touched**: 2-4
- **Expected layers**: config
""")
        rc = triage("auth")
        self.assertEqual(rc, 0)
        data = json.loads((SPECWORK / "_state" / "auth-path.json").read_text())
        self.assertEqual(data["ticket_type"], "high-risk")
        self.assertIn("test-design", data["recommended_path"])

    def test_triage_missing_spec_returns_1(self):
        rc = triage("nonexistent")
        self.assertEqual(rc, 1)

    def test_triage_reason_signals_included(self):
        self._write_spec("kafka-auth", """\
# kafka-auth — Kafka with auth

## Behavior

Consumer receives events. Token validation required.

## Implementation Context

- KafkaListener, SecurityConfig

## Expected Change Scope

- **Expected files touched**: 4-6
- **Expected layers**: listener, config
""")
        rc = triage("kafka-auth")
        self.assertEqual(rc, 0)
        data = json.loads((SPECWORK / "_state" / "kafka-auth-path.json").read_text())
        self.assertEqual(data["ticket_type"], "high-risk")
        self.assertTrue(len(data["signals"]) > 0)
        self.assertIn("high-risk", data["reason"])


class StepCommandsTestCase(unittest.TestCase):

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name)
        self._old_cwd = os.getcwd()
        os.chdir(self.root)
        SPECWORK.mkdir(parents=True, exist_ok=True)
        (SPECWORK / "_state").mkdir(parents=True, exist_ok=True)

    def tearDown(self):
        os.chdir(self._old_cwd)
        self._tmp.cleanup()

    def _write_state(self, slug, current_step="spec", ticket_type="feature"):
        state = {
            "schema_version": 1,
            "slug": slug,
            "ticket_type": ticket_type,
            "current_step": current_step,
            "step_index": 0,
            "retries": 0,
            "max_retries": 2,
            "branch": f"feature/{slug}",
            "base_branch": "main",
        }
        (SPECWORK / "_state" / f"{slug}-state.json").write_text(json.dumps(state), encoding="utf-8")

    def test_current_step_returns_value(self):
        self._write_state("s", current_step="plan")
        rc = cmd_current_step(["s"])
        self.assertEqual(rc, 0)

    def test_current_step_no_state(self):
        rc = cmd_current_step(["nonexistent"])
        self.assertEqual(rc, 1)

    def test_expected_step_matches(self):
        self._write_state("s", current_step="plan")
        rc = cmd_expected_step(["plan", "s"])
        self.assertEqual(rc, 0)

    def test_expected_step_mismatches(self):
        self._write_state("s", current_step="spec")
        rc = cmd_expected_step(["implement", "s"])
        self.assertEqual(rc, 1)

    def test_expected_step_not_in_flow(self):
        self._write_state("s", current_step="implement", ticket_type="trivial")
        rc = cmd_expected_step(["plan", "s"])
        self.assertEqual(rc, 1)

    def test_advance_step_moves_forward(self):
        self._write_state("s", current_step="spec")
        cmd_advance_step(["s"])
        data = json.loads((SPECWORK / "_state" / "s-state.json").read_text())
        self.assertEqual(data["current_step"], "plan")

    def test_advance_step_terminates_at_done(self):
        self._write_state("s", current_step="close")
        cmd_advance_step(["s"])
        data = json.loads((SPECWORK / "_state" / "s-state.json").read_text())
        self.assertEqual(data["current_step"], "done")

    def test_advance_step_done_is_sticky(self):
        self._write_state("s", current_step="done")
        rc = cmd_advance_step(["s"])
        self.assertEqual(rc, 0)
        data = json.loads((SPECWORK / "_state" / "s-state.json").read_text())
        self.assertEqual(data["current_step"], "done")

    def test_advance_step_resets_retries(self):
        self._write_state("s", current_step="implement")
        # bump retries first
        state_path = SPECWORK / "_state" / "s-state.json"
        d = json.loads(state_path.read_text())
        d["retries"] = 2
        state_path.write_text(json.dumps(d))
        cmd_advance_step(["s"])
        d = json.loads(state_path.read_text())
        self.assertEqual(d["retries"], 0)

    def test_set_step_moves_to_target(self):
        self._write_state("s", current_step="spec")
        rc = cmd_set_step(["implement", "s"])
        self.assertEqual(rc, 0)
        data = json.loads((SPECWORK / "_state" / "s-state.json").read_text())
        self.assertEqual(data["current_step"], "implement")

    def test_set_step_rejects_unknown_step(self):
        self._write_state("s", current_step="spec")
        rc = cmd_set_step(["bogus", "s"])
        self.assertEqual(rc, 1)

    def test_set_step_accepts_done(self):
        self._write_state("s", current_step="spec")
        rc = cmd_set_step(["done", "s"])
        self.assertEqual(rc, 0)
        data = json.loads((SPECWORK / "_state" / "s-state.json").read_text())
        self.assertEqual(data["current_step"], "done")

    def test_precheck_passes_when_initialized(self):
        self._write_state("s")
        self.assertEqual(cmd_precheck([]), 0)

    def test_precheck_rejects_when_not_initialized(self):
        # .specwork/_state exists but has no *-state.json
        self.assertEqual(cmd_precheck([]), 1)

    def test_precheck_rejects_when_no_specwork(self):
        import shutil
        shutil.rmtree(SPECWORK)
        self.assertEqual(cmd_precheck([]), 1)

    def test_precheck_rejects_unknown_slug(self):
        self._write_state("s")
        self.assertEqual(cmd_precheck(["other"]), 1)

    def test_precheck_fresh_passes_when_not_initialized(self):
        # right after /f-close: dir may exist but no state
        self.assertEqual(cmd_precheck(["--fresh"]), 0)

    def test_precheck_fresh_rejects_when_already_initialized(self):
        self._write_state("s")
        self.assertEqual(cmd_precheck(["--fresh"]), 1)

    def test_bump_spec_ts_updates_state(self):
        import time
        self._write_state("s")
        state_path = SPECWORK / "_state" / "s-state.json"
        d = json.loads(state_path.read_text())
        d["spec_write_timestamp"] = 1
        state_path.write_text(json.dumps(d))

        before = int(time.time())
        rc = cmd_bump_spec_ts(["s"])
        after = int(time.time())

        self.assertEqual(rc, 0)
        d = json.loads(state_path.read_text())
        self.assertGreaterEqual(d["spec_write_timestamp"], before)
        self.assertLessEqual(d["spec_write_timestamp"], after)

    def test_bump_spec_ts_rejects_unknown_slug(self):
        rc = cmd_bump_spec_ts(["nonexistent"])
        self.assertEqual(rc, 1)

    def test_expected_step_wrong_suggests_next(self):
        import io
        import contextlib
        self._write_state("s", current_step="implement", ticket_type="feature")
        err = io.StringIO()
        with contextlib.redirect_stderr(err):
            cmd_expected_step(["commit", "s"])
        out = err.getvalue()
        self.assertIn("Out of sequence", out)
        self.assertIn("Run next: implement", out)

    def test_expected_step_allows_skip_over_optional(self):
        # high-risk at test-design: test-design/test-impl/review are optional,
        # so commit is reachable by skipping them.
        self._write_state("s", current_step="test-design", ticket_type="high-risk")
        self.assertEqual(cmd_expected_step(["commit", "s"]), 0)

    def test_expected_step_allows_optional_next(self):
        self._write_state("s", current_step="test-design", ticket_type="high-risk")
        self.assertEqual(cmd_expected_step(["test-impl", "s"]), 0)

    def test_expected_step_blocks_skip_over_required(self):
        # feature at implement: implement is required, so commit is not reachable.
        self._write_state("s", current_step="implement", ticket_type="feature")
        self.assertEqual(cmd_expected_step(["commit", "s"]), 1)

    def test_expected_step_blocks_backward(self):
        self._write_state("s", current_step="commit", ticket_type="high-risk")
        self.assertEqual(cmd_expected_step(["test-impl", "s"]), 1)

    def test_advance_anchored_on_completed_step(self):
        # commit reached by skipping optional steps must still land on mr.
        self._write_state("s", current_step="test-design", ticket_type="high-risk")
        self.assertEqual(cmd_advance_step(["s", "commit"]), 0)
        data = json.loads((SPECWORK / "_state" / "s-state.json").read_text())
        self.assertEqual(data["current_step"], "mr")

    def test_advance_without_anchor_uses_current(self):
        self._write_state("s", current_step="test-design", ticket_type="high-risk")
        self.assertEqual(cmd_advance_step(["s"]), 0)
        data = json.loads((SPECWORK / "_state" / "s-state.json").read_text())
        self.assertEqual(data["current_step"], "test-impl")

    def test_advance_preserves_extra_keys(self):
        # advance-step saves state; start.sh's extra keys must survive the round-trip.
        state = {
            "schema_version": 1, "id": "s", "slug": "s", "ticket_type": "feature",
            "current_step": "implement", "step_index": 0, "branch": "feature/s",
            "input_type": "jira", "source_file": ".specwork/_spec/s-source.md",
        }
        (SPECWORK / "_state" / "s-state.json").write_text(json.dumps(state), encoding="utf-8")
        self.assertEqual(cmd_advance_step(["s"]), 0)
        data = json.loads((SPECWORK / "_state" / "s-state.json").read_text())
        self.assertEqual(data["current_step"], "commit")        # updated
        self.assertEqual(data["id"], "s")                        # preserved
        self.assertEqual(data["input_type"], "jira")             # preserved
        self.assertEqual(data["source_file"], ".specwork/_spec/s-source.md")


if __name__ == "__main__":
    unittest.main()
