import json
import tempfile
import os
import unittest
from pathlib import Path

from engine.persistence import (
    load_state, save_state,
    load_rules, save_rules,
    load_cache, save_cache,
    load_plan, save_plan,
    load_spec, load_source,
    rename_slug_in_state,
    SPECWORK,
)


class PersistenceTestCase(unittest.TestCase):

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name)
        self._old_cwd = os.getcwd()
        os.chdir(self.root)
        SPECWORK.mkdir(parents=True, exist_ok=True)

    def tearDown(self):
        os.chdir(self._old_cwd)
        self._tmp.cleanup()

    def _write_state(self, slug: str, data: dict):
        d = SPECWORK / "_state"
        d.mkdir(parents=True, exist_ok=True)
        (d / f"{slug}-state.json").write_text(
            json.dumps(data, indent=2) + "\n", encoding="utf-8")

    # --- state round-trip ---

    def test_save_and_load_state(self):
        data = {"id": "my-feature", "branch": "feature/my-feature", "ticket": "PROJ-1"}
        save_state("my-feature", data)
        loaded = load_state("my-feature")
        self.assertEqual(loaded, data)

    def test_load_state_missing_returns_none(self):
        self.assertIsNone(load_state("nonexistent"))

    # --- rules round-trip ---

    def test_save_and_load_rules(self):
        rules = {"id": "my-feature", "service_rules": ["rule1"]}
        save_rules("my-feature", rules)
        loaded = load_rules("my-feature")
        self.assertEqual(loaded, rules)

    def test_load_rules_missing_returns_none(self):
        self.assertIsNone(load_rules("nonexistent"))

    # --- cache round-trip ---

    def test_save_and_load_cache(self):
        cache = {"notes": ["implemented: Foo.java"]}
        save_cache("my-feature", cache)
        loaded = load_cache("my-feature")
        self.assertEqual(loaded, cache)

    def test_load_cache_missing_returns_none(self):
        self.assertIsNone(load_cache("nonexistent"))

    # --- plan round-trip ---

    def test_save_and_load_plan(self):
        targets = [
            {"path": "src/Foo.java", "change": "Add method", "status": "pending"},
        ]
        save_plan("my-feature", targets)
        loaded = load_plan("my-feature")
        self.assertEqual(len(loaded), 1)
        self.assertEqual(loaded[0]["path"], "src/Foo.java")
        self.assertEqual(loaded[0]["change"], "Add method")

    def test_load_plan_missing_returns_none(self):
        self.assertIsNone(load_plan("nonexistent"))

    # --- spec / source ---

    def test_load_spec(self):
        (SPECWORK / "_spec").mkdir(parents=True, exist_ok=True)
        (SPECWORK / "_spec" / "my-feature-spec.md").write_text(
            "# my feature\n\nBehavior: foo", encoding="utf-8")
        spec = load_spec("my-feature")
        self.assertIsNotNone(spec)
        self.assertIn("foo", spec)

    def test_load_spec_missing_returns_none(self):
        self.assertIsNone(load_spec("nonexistent"))

    def test_load_source(self):
        (SPECWORK / "_spec").mkdir(parents=True, exist_ok=True)
        (SPECWORK / "_spec" / "my-feature-source.md").write_text(
            "PROJ-123: Add feature", encoding="utf-8")
        source = load_source("my-feature")
        self.assertIsNotNone(source)
        self.assertIn("PROJ-123", source)

    def test_load_source_missing_returns_none(self):
        self.assertIsNone(load_source("nonexistent"))

    def test_rename_slug_in_state(self):
        p = self.root / "old-state.json"
        p.write_text(json.dumps({
            "id": "old", "branch": "feature/old", "ticket": None,
            "input_type": "freetext", "spec_file": ".specwork/_spec/old-spec.md",
            "source_title": "keep me",
        }), encoding="utf-8")
        d = rename_slug_in_state(str(p), "ir-70-new", "old", "feature/IR-70-new", "IR-70", "jira")
        self.assertEqual(d["id"], "ir-70-new")
        self.assertEqual(d["branch"], "feature/IR-70-new")
        self.assertEqual(d["ticket"], "IR-70")
        self.assertEqual(d["input_type"], "jira")
        self.assertEqual(d["spec_file"], ".specwork/_spec/ir-70-new-spec.md")
        self.assertEqual(d["source_title"], "keep me")

    def test_rename_slug_no_double_up(self):
        p = self.root / "c-state.json"
        p.write_text(json.dumps({
            "id": "consent", "spec_file": ".specwork/_spec/consent-spec.md",
        }), encoding="utf-8")
        d = rename_slug_in_state(str(p), "ir-70-consent", "consent", "feature/x", "IR-70", "jira")
        self.assertEqual(d["spec_file"], ".specwork/_spec/ir-70-consent-spec.md")


if __name__ == "__main__":
    unittest.main()
