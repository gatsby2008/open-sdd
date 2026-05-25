#!/usr/bin/env python3
"""
End-to-end pipeline integration test for open-sdd.

Creates specs in a temp project, runs commands/triage.sh via subprocess,
and verifies the recommended pipeline path includes f-test-design and
f-test-impl only when the change complexity warrants it.
"""
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

OPENSDD = Path(__file__).resolve().parent.parent
TRIAGE = OPENSDD / "commands" / "triage.sh"


class E2ETriageCase(unittest.TestCase):
    """Sets up a temp project dir with a spec and runs triage.sh."""

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name)
        self._old_cwd = os.getcwd()
        os.chdir(self.root)

    def tearDown(self):
        os.chdir(self._old_cwd)
        self._tmp.cleanup()

    def _write_spec(self, slug, body):
        d = self.root / ".specwork" / "_spec"
        d.mkdir(parents=True, exist_ok=True)
        (d / f"{slug}-spec.md").write_text(body, encoding="utf-8")

    def _run_triage(self, slug):
        r = subprocess.run(
            ["bash", str(TRIAGE), slug],
            capture_output=True, text=True, cwd=self.root,
        )
        self.assertEqual(r.returncode, 0, msg=r.stderr)
        out = self.root / ".specwork" / "_state" / f"{slug}-path.json"
        self.assertTrue(out.exists(), f"Missing path.json: {out}")
        return json.loads(out.read_text())

    def _assert_in_path(self, data, steps):
        path = data["recommended_path"]
        for s in steps:
            self.assertIn(s, path, f"Expected {s} in path {path}")

    def _assert_not_in_path(self, data, steps):
        path = data["recommended_path"]
        for s in steps:
            self.assertNotIn(s, path, f"Did not expect {s} in path {path}")


class TestTriageByTier(E2ETriageCase):

    def test_trivial_skips_test_steps(self):
        self._write_spec("t1", """\
# t1 — Rename welcome copy

## Summary

Rename the welcome banner text on the landing page.

## Behavior

1. This is a copy change: replace "Welcome" with "Hello".

## Implementation Context

- Resource bundle

## Expected Change Scope

- **Expected files touched**: 1
- **Expected layers**:
""")
        data = self._run_triage("t1")
        self.assertEqual(data["ticket_type"], "trivial")
        self._assert_not_in_path(data, ["f-test-design", "f-test-impl", "f-implement"])
        self._assert_in_path(data, ["f-commit", "f-mr"])

    def test_focused_skips_test_and_plan(self):
        self._write_spec("t2", """\
# t2 — Add input validation

## Summary

Reject empty email in the login form.

## Behavior

1. Service validates email is non-empty before processing.

## Implementation Context

- LoginService

## Expected Change Scope

- **Expected files touched**: 1-2
- **Expected layers**: service
""")
        data = self._run_triage("t2")
        self.assertEqual(data["ticket_type"], "focused")
        self._assert_not_in_path(data, ["f-test-design", "f-test-impl", "f-plan"])
        self._assert_in_path(data, ["f-implement", "f-commit", "f-mr"])

    def test_standard_skips_test_steps(self):
        self._write_spec("t3", """\
# t3 — Offer listing endpoint

## Summary

New REST endpoint to list active offers.

## Behavior

1. Controller receives GET /api/v1/offers.
2. Service queries the repository.
3. Returns a list of OfferDTO.

## Implementation Context

- OfferController, OfferService, OfferRepository

## Expected Change Scope

- **Expected files touched**: 3-6
- **Expected layers**: controller, service, repository
""")
        data = self._run_triage("t3")
        self.assertEqual(data["ticket_type"], "standard")
        self._assert_not_in_path(data, ["f-test-design", "f-test-impl"])
        self._assert_in_path(data, ["f-plan", "f-implement", "f-commit", "f-mr"])

    def test_high_risk_kafka_includes_test_steps(self):
        self._write_spec("t4", """\
# t4 — Kafka event producer

## Summary

Publish OfferActivated events to Kafka.

## Behavior

1. A Kafka consumer receives the state change.
2. Producer publishes with auth token.

## Implementation Context

- KafkaListener, OfferEventProducer

## Expected Change Scope

- **Expected files touched**: 5-8
- **Expected layers**: listener, service, config
""")
        data = self._run_triage("t4")
        self.assertEqual(data["ticket_type"], "high-risk")
        self._assert_in_path(data, ["f-test-design", "f-test-impl"])

    def test_high_risk_migration_includes_test_steps(self):
        self._write_spec("t5", """\
# t5 — Flyway migration

## Summary

Add consent_given column to the user table.

## Behavior

1. Flyway migration runs on startup.
2. Entity gets the new column mapping.

## Implementation Context

- UserRepo, migration files

## Expected Change Scope

- **Expected files touched**: 3-5
- **Expected layers**: repository, service
""")
        data = self._run_triage("t5")
        self.assertEqual(data["ticket_type"], "high-risk")
        self._assert_in_path(data, ["f-test-design", "f-test-impl"])

    def test_high_risk_auth_includes_test_steps(self):
        self._write_spec("t6", """\
# t6 — Auth token validation

## Summary

Add JWT validation in SecurityConfig.

## Behavior

1. Authentication filter validates the token.
2. Returns 401 if invalid.

## Implementation Context

- SecurityConfig, JwtAuthFilter

## Expected Change Scope

- **Expected files touched**: 2-4
- **Expected layers**: config
""")
        data = self._run_triage("t6")
        self.assertEqual(data["ticket_type"], "high-risk")
        self._assert_in_path(data, ["f-test-design", "f-test-impl"])


if __name__ == "__main__":
    unittest.main()
