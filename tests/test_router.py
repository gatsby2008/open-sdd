import unittest

from engine.router import next_step, FLOW_MAP, flow_for, OPTIONAL_STEPS, is_optional


class RouterTestCase(unittest.TestCase):

    # --- FLOW_MAP structure ---

    def test_flow_map_has_expected_types(self):
        expected = {"feature", "bugfix", "refactor", "chore", "high-risk",
                     "standard", "focused", "trivial", "security_fix"}
        self.assertEqual(set(FLOW_MAP.keys()), expected)

    def test_feature_flow_is_full(self):
        self.assertEqual(FLOW_MAP["feature"],
                         ["spec", "plan", "implement", "commit", "mr", "close"])

    def test_generic_test_step_removed(self):
        # tests are tracked only in high-risk via test-design/test-impl now
        for t in ("feature", "bugfix", "refactor", "security_fix"):
            self.assertNotIn("test", FLOW_MAP[t])

    def test_high_risk_has_test_pair(self):
        self.assertEqual(
            FLOW_MAP["high-risk"],
            ["plan", "implement", "test-design", "test-impl", "commit", "mr", "close"])

    def test_review_is_not_a_tracked_step(self):
        # code review is an independent command, not a flow step (matches claude-tools)
        for flow in FLOW_MAP.values():
            self.assertNotIn("review", flow)

    def test_optional_steps(self):
        self.assertEqual(OPTIONAL_STEPS, {"test-design", "test-impl"})
        self.assertTrue(is_optional("test-impl"))
        self.assertFalse(is_optional("implement"))

    def test_bugfix_skips_plan(self):
        self.assertNotIn("plan", FLOW_MAP["bugfix"])

    def test_refactor_skips_spec(self):
        self.assertNotIn("spec", FLOW_MAP["refactor"])

    def test_chore_minimal(self):
        self.assertEqual(FLOW_MAP["chore"],
                         ["implement", "commit", "mr", "close"])

    def test_trivial_skips_implement(self):
        self.assertNotIn("implement", FLOW_MAP["trivial"])

    def test_security_fix_includes_spec(self):
        self.assertIn("spec", FLOW_MAP["security_fix"])
        self.assertNotIn("review", FLOW_MAP["security_fix"])

    # --- next_step() ---

    def test_next_step_returns_current_when_under_retry_limit(self):
        self.assertEqual(
            next_step("feature", "implement", retries=1), "implement")

    def test_next_step_advances_when_retries_exhausted(self):
        self.assertEqual(
            next_step("feature", "implement", retries=2), "commit")

    def test_next_step_advances_bugfix(self):
        self.assertEqual(
            next_step("bugfix", "spec", retries=2), "implement")

    def test_next_step_advances_trivial(self):
        self.assertEqual(
            next_step("trivial", "commit", retries=2), "mr")

    def test_next_step_returns_done_at_flow_end(self):
        self.assertEqual(
            next_step("feature", "close", retries=2), "done")

    def test_next_step_returns_done_at_end_trivial(self):
        self.assertEqual(
            next_step("trivial", "close", retries=2), "done")

    def test_next_step_returns_first_step_for_unknown_current(self):
        self.assertEqual(
            next_step("feature", "nonexistent", retries=0), "spec")

    def test_next_step_falls_back_to_feature_for_unknown_type(self):
        self.assertEqual(
            next_step("unknown_type", "spec", retries=2), "plan")

    # --- flow_for() ---

    def test_flow_for_known_type(self):
        self.assertEqual(flow_for("feature"), FLOW_MAP["feature"])

    def test_flow_for_unknown_falls_back_to_feature(self):
        self.assertEqual(flow_for("bogus"), FLOW_MAP["feature"])

    # --- custom max_retries ---

    def test_next_step_custom_max_retries(self):
        self.assertEqual(
            next_step("feature", "implement", retries=2, max_retries=3), "implement")
        self.assertEqual(
            next_step("feature", "implement", retries=3, max_retries=3), "commit")


if __name__ == "__main__":
    unittest.main()
