"""Tier override (/f-spec --tier) and the plan-required gate of /f-implement."""
import json
import os
import subprocess
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from io import StringIO
from pathlib import Path

from engine import tier
from engine.cli import cmd_implement_check

REPO_ROOT = Path(__file__).resolve().parent.parent
TRIAGE = REPO_ROOT / "commands" / "triage.sh"

# "does not publish to Kafka" still matches the `kafka` keyword → high-risk.
KAFKA_SPEC = """# x — summary

## Behavior

1. **B1** — Returns the summary. It does not publish any event to Kafka.

## Implementation Context

- MenuController

## Expected Change Scope

- Expected layers touched: controller
- Expected files touched: 2

## Open Questions

"""

TRIVIAL_SPEC = KAFKA_SPEC.replace(
    "Returns the summary. It does not publish any event to Kafka.", "Fix a typo in the greeting message.")


class TierCase(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self._old = os.getcwd()
        os.chdir(self._tmp.name)
        Path(".specwork/_spec").mkdir(parents=True)
        Path(".specwork/_state").mkdir(parents=True)
        Path(".specwork/_state/x-state.json").write_text('{"id": "x", "ticket_type": "feature"}\n')
        Path(".specwork/_state/x-rules.json").write_text("{}\n")
        Path(".specwork/_state/x-implementation-cache.json").write_text("{}\n")

    def tearDown(self):
        os.chdir(self._old)
        self._tmp.cleanup()

    def spec(self, body):
        Path(".specwork/_spec/x-spec.md").write_text(body)

    def triage(self, *args):
        return subprocess.run(["bash", str(TRIAGE), "x", *args], capture_output=True, text=True)

    def path_json(self):
        return json.loads(Path(".specwork/_state/x-path.json").read_text())

    def implement_check(self):
        with redirect_stdout(StringIO()) as out, redirect_stderr(StringIO()):
            rc = cmd_implement_check(["x"])
        return rc, out.getvalue()


class TestTierOverride(TierCase):
    def test_force_lower_tier(self):
        self.spec(KAFKA_SPEC)
        r = self.triage("--tier", "focused", "read-only; criterion 5 negates Kafka")
        self.assertEqual(r.returncode, 0, r.stderr)
        d = self.path_json()
        self.assertEqual((d["ticket_type"], d["complexity"]), ("focused", "LOW"))
        self.assertEqual(d["recommended_path"], ["f-implement", "f-commit", "f-mr"])
        self.assertEqual(d["override"]["auto_tier"], "high-risk")
        self.assertIn("Override: forced focused (auto: high-risk", r.stderr)
        state = json.loads(Path(".specwork/_state/x-state.json").read_text())
        self.assertEqual(state["ticket_type"], "focused")

    def test_force_higher_tier(self):
        self.spec(TRIVIAL_SPEC)
        r = self.triage("--tier", "high-risk", "touches the billing contract")
        self.assertEqual(r.returncode, 0, r.stderr)
        d = self.path_json()
        self.assertEqual(d["ticket_type"], "high-risk")
        self.assertEqual(d["override"]["auto_tier"], "trivial")
        self.assertIn("f-test-design", d["recommended_path"])

    def test_reason_is_mandatory_and_nothing_is_written(self):
        self.spec(KAFKA_SPEC)
        r = self.triage("--tier", "focused")
        self.assertEqual(r.returncode, 2)
        self.assertFalse(Path(".specwork/_state/x-path.json").exists())

    def test_unknown_tier_is_rejected(self):
        self.spec(KAFKA_SPEC)
        self.assertEqual(self.triage("--tier", "huge", "r").returncode, 2)
        self.assertFalse(Path(".specwork/_state/x-path.json").exists())

    def test_override_is_sticky_and_auto_drops_it(self):
        self.spec(KAFKA_SPEC)
        self.triage("--tier", "focused", "negated Kafka")
        self.assertEqual(self.triage().returncode, 0)
        self.assertEqual(self.path_json()["ticket_type"], "focused")
        self.triage("--tier", "auto")
        d = self.path_json()
        self.assertEqual(d["ticket_type"], "high-risk")
        self.assertNotIn("override", d)

    def test_payload_shape_is_unchanged_besides_override(self):
        self.spec(KAFKA_SPEC)
        self.triage()
        auto_keys = set(self.path_json())
        self.triage("--tier", "standard", "r")
        self.assertEqual(set(self.path_json()) - auto_keys, {"override"})

    def test_apply_override_validates(self):
        with self.assertRaises(ValueError):
            tier.apply_override({"ticket_type": "focused"}, "huge", "r")
        with self.assertRaises(ValueError):
            tier.apply_override({"ticket_type": "focused"}, "focused", "  ")


class TestPlanRequiredGate(TierCase):
    def test_high_risk_without_plan_is_blocked(self):
        self.spec(KAFKA_SPEC)
        self.triage()
        rc, out = self.implement_check()
        self.assertEqual(rc, 1)
        self.assertIn("PLAN_REQUIRED", out)

    def test_forcing_a_lower_tier_lifts_the_gate(self):
        self.spec(KAFKA_SPEC)
        self.triage("--tier", "focused", "negated Kafka")
        self.assertEqual(self.implement_check()[0], 0)

    def test_forcing_high_risk_engages_the_gate(self):
        self.spec(TRIVIAL_SPEC)
        self.triage()
        self.assertEqual(self.implement_check()[0], 0)
        self.triage("--tier", "high-risk", "billing")
        self.assertEqual(self.implement_check(), (1, "PLAN_REQUIRED\n"))

    def test_override_block_wins_over_ticket_type(self):
        Path(".specwork/_state/x-path.json").write_text(json.dumps(
            {"ticket_type": "high-risk", "override": {"tier": "focused", "reason": "r"}}))
        self.assertFalse(tier.plan_required("x"))

    def test_existing_plan_passes(self):
        self.spec(KAFKA_SPEC)
        self.triage()
        Path(".specwork/_plan").mkdir()
        Path(".specwork/_plan/x-plan.md").write_text("# plan\n")
        self.assertEqual(self.implement_check()[0], 0)

    def test_no_path_json_passes(self):
        self.spec(KAFKA_SPEC)
        self.assertEqual(self.implement_check()[0], 0)


if __name__ == "__main__":
    unittest.main()


class TestSingleTriage(TierCase):
    """triage.sh and `engine.cli triage` are the same implementation (engine/triage.py)."""

    def test_wrapper_and_cli_write_the_same_path_json(self):
        self.spec(KAFKA_SPEC)
        self.assertEqual(self.triage().returncode, 0)
        from_sh = self.path_json()
        env = {**os.environ, "PYTHONPATH": str(REPO_ROOT)}
        r = subprocess.run(["python3", "-m", "engine.cli", "triage", "x"], capture_output=True, text=True, env=env)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(self.path_json(), from_sh)
        self.assertEqual(json.loads(r.stdout), from_sh)

    def test_focused_is_low_with_skip(self):
        from engine.triage import classify
        result = classify(TRIVIAL_SPEC.replace("Fix a typo in the greeting message.", "Add a field."))
        self.assertEqual((result["ticket_type"], result["complexity"]), ("focused", "LOW"))
        self.assertEqual(result["skip"], ["f-plan", "f-test-design", "f-test-impl"])

    def test_mixed_case_keyword_matches(self):
        from engine.triage import classify
        spec = KAFKA_SPEC.replace("It does not publish any event to Kafka.", "Fetch with useSWR.")
        self.assertEqual(classify(spec)["ticket_type"], "high-risk")
