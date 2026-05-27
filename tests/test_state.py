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
            current_step="implement",
            retries=0,
            max_retries=2,
        )
        defaults.update(overrides)
        return PipelineState(**defaults)

    def test_defaults(self):
        s = PipelineState(slug="my-slug")
        self.assertEqual(s.slug, "my-slug")
        self.assertEqual(s.ticket_type, "feature")
        self.assertEqual(s.current_step, "start")
        self.assertEqual(s.retries, 0)
        self.assertEqual(s.max_retries, 2)
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

    def test_should_retry_under_limit(self):
        s = self._make_state(retries=0)
        self.assertTrue(s.should_retry())

        s.retries = 1
        self.assertTrue(s.should_retry())

    def test_should_not_retry_at_limit(self):
        s = self._make_state(retries=2)
        self.assertFalse(s.should_retry())

        s.retries = 3
        self.assertFalse(s.should_retry())

    def test_escalate_forces_max_retries_and_records_reason(self):
        s = self._make_state(retries=1)
        s.escalate("Database migration detected, needs human review")
        self.assertEqual(s.retries, s.max_retries)
        self.assertEqual(len(s.escalations), 1)
        self.assertEqual(s.escalations[0]["reason"], "Database migration detected, needs human review")
        self.assertEqual(s.escalations[0]["attempts"], 1)

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

    def test_from_dict_restores_cache(self):
        d = {
            "slug": "test-feature",
            "ticket": "PROJ-123",
            "ticket_type": "feature",
            "branch": "feature/test-feature",
            "base_branch": "main",
            "current_step": "implement",
            "retries": 1,
            "max_retries": 3,
            "spec_file": "",
            "plan_file": "",
            "source_file": "",
            "rules_file": "",
            "cache_file": "",
            "metrics_mode": "none",
            "schema_version": 1,
            "spec_write_timestamp": 0,
            "step_index": 0,
            "escalations": [],
        }
        s = PipelineState.from_dict(d)
        self.assertEqual(s.slug, "test-feature")
        self.assertEqual(s.max_retries, 3)
        self.assertEqual(s.retries, 1)

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

    def test_next_step_delegates_to_router(self):
        s = self._make_state(ticket_type="feature", current_step="implement", retries=2)
        next_s = s.next_step()
        self.assertEqual(next_s, "commit")

    def test_next_step_retries_when_under_limit(self):
        s = self._make_state(ticket_type="feature", current_step="implement", retries=1)
        next_s = s.next_step()
        self.assertEqual(next_s, "implement")


if __name__ == "__main__":
    unittest.main()
