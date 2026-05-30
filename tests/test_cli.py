import json
import tempfile
import os
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

from engine.cli import (
    triage,
    cmd_precheck,
    cmd_bump_spec_ts,
    cmd_risk_signals,
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

    def _write_state(self, slug, ticket_type="feature"):
        state = {
            "schema_version": 1,
            "slug": slug,
            "ticket_type": ticket_type,
            "branch": f"feature/{slug}",
            "base_branch": "main",
        }
        (SPECWORK / "_state" / f"{slug}-state.json").write_text(json.dumps(state), encoding="utf-8")

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


class RiskSignalsTestCase(CliTestCase):
    """cmd_risk_signals prints concrete (deterministic) risk labels, one per line.

    /f-auto uses this to decide whether to pause and ask about the costly test
    steps — only hard keyword matches count, not the fuzzy triage tier.
    """

    def _signals(self, slug):
        import io
        import contextlib
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            rc = cmd_risk_signals([slug])
        self.assertEqual(rc, 0)
        return [ln for ln in out.getvalue().splitlines() if ln.strip()]

    def test_db_migration_signal(self):
        self._write_spec("migrate", "# m\n## Behavior\nAdd a Flyway migration and alter table users.\n")
        self.assertIn("db-migration", self._signals("migrate"))

    def test_auth_signal(self):
        self._write_spec("auth", "# a\n## Behavior\nValidate the JWT and check authorization.\n")
        self.assertIn("auth-security", self._signals("auth"))

    def test_clean_spec_has_no_signals(self):
        self._write_spec("copy", "# c\n## Behavior\nRename a label on the landing page.\n")
        self.assertEqual(self._signals("copy"), [])

    def test_missing_spec_has_no_signals(self):
        # No spec file → no signals, still rc 0 (auto.sh treats empty as "proceed").
        self.assertEqual(self._signals("ghost"), [])


if __name__ == "__main__":
    unittest.main()
