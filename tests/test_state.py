import tempfile
import os
import unittest
from pathlib import Path

from engine.state import PipelineState, load_pipeline_state, save_pipeline_state
from engine.persistence import SPECWORK


class PipelineStateTestCase(unittest.TestCase):

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name)
        self._old_cwd = os.getcwd()
        os.chdir(self.root)

    def tearDown(self):
        os.chdir(self._old_cwd)
        self._tmp.cleanup()

    def _make_state(self, **overrides) -> PipelineState:
        defaults = dict(
            slug="test-feature",
            ticket="PROJ-123",
            ticket_type="feature",
            branch="feature/test-feature",
            base_branch="main",
        )
        defaults.update(overrides)
        return PipelineState(**defaults)

    def test_defaults(self):
        s = PipelineState(slug="my-slug")
        self.assertEqual(s.slug, "my-slug")
        self.assertEqual(s.ticket_type, "feature")
        self.assertEqual(s.escalations, [])

    def test_properties_return_correct_paths(self):
        s = PipelineState(slug="my-feature")
        self.assertTrue(str(s.spec_path).endswith("_spec/my-feature-spec.md"))
        self.assertTrue(str(s.plan_json_path).endswith("_plan/my-feature-plan.json"))
        self.assertTrue(str(s.plan_md_path).endswith("_plan/my-feature-plan.md"))
        self.assertTrue(str(s.state_path).endswith("_state/my-feature-state.json"))
        self.assertTrue(str(s.rules_path).endswith("_state/my-feature-rules.json"))
        self.assertTrue(str(s.cache_path).endswith("_state/my-feature-implementation-cache.json"))
        self.assertTrue(str(s.source_path).endswith("_spec/my-feature-source.md"))

    def test_escalate_appends_reason(self):
        s = self._make_state()
        s.escalate("Database migration detected, needs human review")
        self.assertEqual(len(s.escalations), 1)
        self.assertEqual(s.escalations[0]["reason"], "Database migration detected, needs human review")

    def test_escalate_appends_multiple(self):
        s = self._make_state()
        s.escalate("First issue")
        s.escalate("Second issue")
        self.assertEqual(len(s.escalations), 2)

    def test_to_dict_excludes_cache(self):
        # the implementation cache lives in its own file, never in state.json
        d = self._make_state().to_dict()
        self.assertNotIn("cache", d)
        self.assertEqual(d["slug"], "test-feature")

    def test_from_dict_preserves_extras(self):
        # Forward-compat: unknown keys (e.g. legacy current_step) ride along in
        # state.extra so save→load round-trips don't lose data. Drop only known
        # noise like "cache".
        d = {
            "slug": "test-feature",
            "ticket": "PROJ-123",
            "ticket_type": "feature",
            "branch": "feature/test-feature",
            "base_branch": "main",
            "spec_file": "",
            "plan_file": "",
            "source_file": "",
            "rules_file": "",
            "cache_file": "",
            "metrics_mode": "none",
            "schema_version": 1,
            "spec_write_timestamp": 0,
            "escalations": [],
            # Legacy keys from pre-strip state.json — should be preserved in extra.
            "current_step": "implement",
            "step_index": 2,
        }
        s = PipelineState.from_dict(d)
        self.assertEqual(s.slug, "test-feature")
        self.assertEqual(s.extra.get("current_step"), "implement")

    def test_from_dict_drops_stray_cache_key(self):
        # a legacy "cache" key on disk must be dropped, not leaked into extra and
        # re-written to state.json on the next save.
        d = {"slug": "s", "cache": {"notes": ["x"]}}
        s = PipelineState.from_dict(d)
        self.assertFalse(hasattr(s, "cache"))
        self.assertNotIn("cache", s.to_dict())
        self.assertNotIn("cache", s.extra)

    def test_round_trip_persistence(self):
        s = self._make_state()
        SPECWORK.mkdir(parents=True, exist_ok=True)
        (SPECWORK / "_state").mkdir(parents=True, exist_ok=True)
        save_pipeline_state(s)

        loaded = load_pipeline_state("test-feature")
        self.assertIsNotNone(loaded)
        self.assertEqual(loaded.slug, s.slug)
        self.assertEqual(loaded.branch, s.branch)
        self.assertEqual(loaded.ticket, s.ticket)

    def test_load_pipeline_state_returns_none_for_missing(self):
        result = load_pipeline_state("nonexistent")
        self.assertIsNone(result)


if __name__ == "__main__":
    unittest.main()
