"""engine/ingest.py — the raw -> wiki planner behind /doc-ingest."""
import os
import tempfile
import unittest
from datetime import datetime
from pathlib import Path

from engine import ingest

DOCS = (
    "service-catalog/leads-service.md",
    "adr-registry/leads-service/PROJ-1-ADR-001-x.md",
    "spec-registry/leads-service/proj-2-spec.md",
    "templates/spec.md",                      # scaffolds are never compiled
)


class IngestCase(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        # resolve() so macOS /var -> /private/var does not skew path assertions
        self.vault = Path(self._tmp.name).resolve()
        self.raw = self.vault / "raw"
        self.wiki = self.vault / "wiki"
        for rel in DOCS:
            path = self.raw / rel
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("# doc\n", encoding="utf-8")
            self.set_day(rel, "2026-01-01")

    def tearDown(self):
        self._tmp.cleanup()

    # -- helpers ----------------------------------------------------------
    def set_day(self, rel, iso):
        """Pin a raw doc's mtime to a calendar day (the planner's watermark unit)."""
        ts = datetime.fromisoformat(iso + "T12:00:00").timestamp()
        os.utime(self.raw / rel, (ts, ts))

    def write_log(self, *stamps):
        self.wiki.mkdir(exist_ok=True)
        body = "".join(f"## [{s}] compile | x\n\n" for s in stamps)
        (self.wiki / "log.md").write_text("# Activity Log\n\n" + body, encoding="utf-8")

    def make_wiki(self):
        self.wiki.mkdir(exist_ok=True)


class TestLayout(IngestCase):
    def test_no_wiki_layer(self):
        p = ingest.plan(self.raw)
        self.assertFalse(p.has_wiki)
        self.assertIsNone(p.wiki)
        self.assertIn("(none — no wiki/ sibling of raw/)", ingest.render(p))

    def test_wiki_and_schema_detected(self):
        self.make_wiki()
        (self.vault / "CLAUDE.md").write_text("# schema\n", encoding="utf-8")
        p = ingest.plan(self.raw)
        self.assertTrue(p.has_wiki)
        self.assertEqual(p.wiki, self.wiki)
        self.assertEqual(p.schema, self.vault / "CLAUDE.md")

    def test_agents_md_accepted_as_schema(self):
        self.make_wiki()
        (self.vault / "AGENTS.md").write_text("# schema\n", encoding="utf-8")
        self.assertEqual(ingest.plan(self.raw).schema, self.vault / "AGENTS.md")

    def test_schema_absent(self):
        self.make_wiki()
        self.assertIsNone(ingest.plan(self.raw).schema)

    def test_raw_root_is_resolved(self):
        self.make_wiki()
        p = ingest.plan(Path(str(self.raw) + "/../raw"))
        self.assertEqual(p.raw, self.raw.resolve())


class TestWatermark(IngestCase):
    def test_newest_log_entry_wins(self):
        self.write_log("2026-02-01", "2026-05-09", "2026-03-01")
        self.assertEqual(ingest.log_watermark(self.wiki), "2026-05-09")

    def test_no_log_is_never(self):
        self.make_wiki()
        self.assertEqual(ingest.log_watermark(self.wiki), "never")

    def test_log_without_entries_is_never(self):
        self.make_wiki()
        (self.wiki / "log.md").write_text("# Activity Log\n\nno entries yet\n", encoding="utf-8")
        self.assertEqual(ingest.log_watermark(self.wiki), "never")

    def test_pending_is_what_changed_after_the_watermark(self):
        self.write_log("2026-03-01")
        self.set_day("service-catalog/leads-service.md", "2026-04-01")
        p = ingest.plan(self.raw)
        self.assertEqual(p.watermark, "2026-03-01")
        self.assertEqual([rel for rel, _ in p.pending], ["service-catalog/leads-service.md"])

    def test_equal_day_is_not_pending(self):
        self.write_log("2026-03-01")
        self.set_day("service-catalog/leads-service.md", "2026-03-01")
        self.assertEqual(ingest.plan(self.raw).pending, [])

    def test_never_ingested_means_everything_pending(self):
        self.make_wiki()
        p = ingest.plan(self.raw)
        self.assertEqual(p.watermark, "never")
        self.assertEqual(len(p.pending), 3)          # templates/ excluded

    def test_templates_are_skipped(self):
        self.make_wiki()
        rels = [rel for rel, _ in ingest.plan(self.raw).pending]
        self.assertNotIn("templates/spec.md", rels)

    def test_pending_is_newest_first(self):
        self.make_wiki()
        self.set_day("service-catalog/leads-service.md", "2026-01-05")
        self.set_day("spec-registry/leads-service/proj-2-spec.md", "2026-01-09")
        self.assertEqual([rel for rel, _ in ingest.plan(self.raw).pending][:2],
                         ["spec-registry/leads-service/proj-2-spec.md",
                          "service-catalog/leads-service.md"])


class TestSelection(IngestCase):
    def setUp(self):
        super().setUp()
        self.write_log("2026-01-01")
        self.set_day("service-catalog/leads-service.md", "2026-02-01")

    def test_auto_selects_the_pending_docs(self):
        p = ingest.plan(self.raw)
        self.assertEqual(p.mode, "auto")
        self.assertEqual(p.selected, ["service-catalog/leads-service.md"])

    def test_auto_with_nothing_pending(self):
        self.set_day("service-catalog/leads-service.md", "2026-01-01")
        p = ingest.plan(self.raw)
        self.assertEqual(p.selected, [])
        self.assertIn("nothing — the wiki already covers every raw doc", ingest.render(p))

    def test_relative_path_under_raw(self):
        p = ingest.plan(self.raw, "adr-registry/leads-service/PROJ-1-ADR-001-x.md")
        self.assertEqual(p.mode, "path")
        self.assertEqual(p.selected, ["adr-registry/leads-service/PROJ-1-ADR-001-x.md"])
        self.assertEqual(p.error, "")

    def test_absolute_path_under_raw(self):
        p = ingest.plan(self.raw, str(self.raw / "spec-registry/leads-service/proj-2-spec.md"))
        self.assertEqual(p.selected, ["spec-registry/leads-service/proj-2-spec.md"])

    def test_path_outside_raw_is_rejected(self):
        (self.vault / "CLAUDE.md").write_text("# schema\n", encoding="utf-8")
        p = ingest.plan(self.raw, str(self.vault / "CLAUDE.md"))
        self.assertIn("outside", p.error)
        self.assertEqual(p.selected, [])

    def test_missing_source_is_rejected(self):
        p = ingest.plan(self.raw, "service-catalog/nope.md")
        self.assertIn("Source not found", p.error)

    def test_non_markdown_is_rejected(self):
        (self.raw / "notes.txt").write_text("x", encoding="utf-8")
        self.assertIn("not a markdown file", ingest.plan(self.raw, "notes.txt").error)

    def test_session_mode(self):
        p = ingest.plan(self.raw, "session")
        self.assertEqual(p.mode, "session")
        self.assertEqual(p.selected, [])
        self.assertIn("Selected: session", ingest.render(p))


class TestRender(IngestCase):
    def test_layout_lines(self):
        self.write_log("2026-03-01")
        out = ingest.render(ingest.plan(self.raw))
        self.assertIn(f"Vault: {self.vault}", out)
        self.assertIn(f"Raw: {self.raw.resolve()}", out)
        self.assertIn(f"Wiki: {self.wiki}", out)
        self.assertIn("Last ingest: 2026-03-01", out)
        self.assertIn("Un-ingested: 0 raw doc(s) modified after 2026-03-01", out)

    def test_never_ingested_wording(self):
        self.make_wiki()
        self.assertIn("the wiki has no log entry yet", ingest.render(ingest.plan(self.raw)))

    def test_long_pending_list_is_capped(self):
        self.make_wiki()
        extra = 5
        for i in range(ingest.LIST_LIMIT + extra):
            path = self.raw / "service-catalog" / f"svc-{i:03d}.md"
            path.write_text("# doc\n", encoding="utf-8")
        out = ingest.render(ingest.plan(self.raw))
        # 3 base docs + LIST_LIMIT + extra, minus the LIST_LIMIT printed.
        self.assertIn(f"… and {3 + extra} more", out)

    def test_selected_count_for_auto(self):
        self.make_wiki()
        self.assertIn("Selected (auto): 3 un-ingested source(s)",
                      ingest.render(ingest.plan(self.raw)))


if __name__ == "__main__":
    unittest.main()
