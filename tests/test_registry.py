"""engine/registry.py — selective retrieval behind /doc-ask."""
import os
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from engine import registry
from engine.registry import ask, extract_terms, load_docs, parse_query, select

FILLER = "\n".join(f"Filler line {i} about unrelated plumbing." for i in range(400))

FIXTURE = {
    # catalogs: flat <service>.md plus extra docs under docs/<service>/
    "service-catalog/leads-service.md":
        "# Service: leads-service\n\n> Last updated: 2026-06-07\n\n## Overview\nLeads.\n\n"
        "## Publishes (SNS)\n- `LeadCreated` on topic lead-events\n\n"
        "## Endpoints\n| GET | /api/v1/leads |\n\n## Background Jobs\n" + FILLER + "\n",
    "service-catalog/marketing-service.md":
        "# Service: marketing-service\n\n## Consumes (SQS)\n"
        "- `LeadCreated` from marketing-lead-events-queue\n\n## Jobs\n" + FILLER + "\n",
    "service-catalog/consent-service.md":
        "# Service: consent-service\n\n## Consumes (SQS)\n- `LeadCreated` via consent queue\n"
        "\n## Endpoints\n| POST | /api/v1/consent |\n\n## Jobs\n" + FILLER + "\n",
    "service-catalog/docs/leads-service/decisions.md":
        "# Leads decisions\n\nNotes about batching.\n",
    "service-catalog/.hidden/skip.md": "# hidden\nLeadCreated\n",
    # ADRs
    "adr-registry/leads-service/PROJ-1-ADR-001-sns-fanout.md":
        "---\ntitle: SNS fan-out for lead events\ndate: 2026-05-01\n---\n"
        "# ADR-001\n## Context\nLeadCreated had to reach many consumers.\n"
        "## Decision\nPublish via SNS fan-out.\n",
    "adr-registry/consent-service/PROJ-2-ADR-001-retries.md":
        "---\ntitle: Retry consent sends with backoff\ndate: 2026-07-01\n---\n"
        "## Decision\nExponential backoff for retries.\n",
    # specs: only *-spec.md count
    "spec-registry/leads-service/proj-3-spec.md":
        "# Dedupe\n## Behavior\nSkip dedupe when applicationId is null.\n"
        "## Open Questions\n- [x] **#1** Old — resolved: yes\n- [ ] **#2** Who owns the TTL?\n",
    "spec-registry/consent-service/proj-4-spec.md":
        "# Consent\n## Open Questions\n- [x] **#1** Done — resolved: ok\n",
    "spec-registry/consent-service/notes.md": "# not a spec\n",
    # investigations, deliberately written newest-first on disk
    "investigation-registry/report-service/2026-08-01-reporttoken-again.md":
        "---\ntitle: ReportToken reused again\ndate: 2026-08-01\ntype: bug\n---\nReportToken reuse.\n",
    "investigation-registry/report-service/2026-03-01-reporttoken-reuse.md":
        "---\ntitle: ReportToken reuse\ndate: 2026-03-01\ntype: bug\n---\nReportToken reuse first seen.\n",
    "investigation-registry/templates/ignored.md": "# template\nReportToken\n",
}


class RegistryCase(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name) / "raw"
        for rel, content in FIXTURE.items():
            p = self.root / rel
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text(content)
        self._env = mock.patch.dict(os.environ, {"OPEN_SDD_DOC_HOME": str(self.root)})
        self._env.start()

    def tearDown(self):
        self._env.stop()
        self._tmp.cleanup()

    def run_select(self, question, budget=4_000):
        q = parse_query([question])
        return select(q, load_docs(self.root, q.types), budget)


class TestParseQuery(unittest.TestCase):
    def test_no_filters_means_all_registries(self):
        q = parse_query(["who consumes LeadCreated?"])
        self.assertEqual(q.types, list(registry.REGISTRIES))
        self.assertFalse(q.explicit_types)
        self.assertIsNone(q.service)

    def test_filter_variants_and_aliases(self):
        for args in (["type:adr why"], ["type: adr why"], ["--type", "adr", "why"],
                     ["--type=adrs why"], ["why TYPE:decisions"]):
            with self.subTest(args):
                q = parse_query(args)
                self.assertEqual(q.types, ["adr"])
                self.assertEqual(q.text, "why")

    def test_spanish_alias_and_multiple(self):
        self.assertEqual(parse_query(["type:investigaciones x"]).types, ["investigation"])
        self.assertEqual(parse_query(["type:spec,catalogo x"]).types, ["catalog", "spec"])

    def test_unknown_type_warns_and_is_ignored(self):
        q = parse_query(["type:arch what"])
        self.assertEqual(q.types, list(registry.REGISTRIES))
        self.assertTrue(any("arch" in w for w in q.warnings))

    def test_service_filter(self):
        q = parse_query(["service:Consent-Service retries?"])
        self.assertEqual(q.service, "consent-service")
        self.assertEqual(q.text, "retries?")

    def test_prose_type_is_not_a_filter(self):
        q = parse_query(["what type of retries do we use"])
        self.assertEqual(q.warnings, [])
        self.assertIn("type of retries", q.text)


class TestExtractTerms(unittest.TestCase):
    def test_identifiers_kept_stopwords_dropped(self):
        terms = dict(extract_terms("Who consumes the LeadCreated event from /api/v1/consent?"))
        self.assertIn("leadcreated", terms)
        self.assertTrue(terms["leadcreated"])
        self.assertIn("/api/v1/consent", terms)
        self.assertIn("consume", terms)            # plural 's' stripped
        self.assertNotIn("the", terms)
        self.assertNotIn("who", terms)

    def test_spanish_stopwords_with_accents(self):
        terms = dict(extract_terms("¿quién consume LeadCreated y por qué?"))
        self.assertNotIn("quién", terms)
        self.assertNotIn("qué", terms)
        self.assertIn("leadcreated", terms)


class TestStemming(unittest.TestCase):
    """Regressions found against a real registry (20-question eval, 2026-11-02)."""

    def terms(self, text):
        return dict(extract_terms(text))

    def test_english_es_plural(self):
        self.assertIn("push", self.terms("duplicate pushes"))
        self.assertIn("publish", self.terms("who publishes it"))

    def test_long_words_meet_across_languages(self):
        stem = next(iter(self.terms("duplicados")))
        self.assertIn(stem, "duplicate")
        self.assertIn(stem, "duplicados")
        self.assertIn(next(iter(self.terms("invalidated"))), "invalidate the session")

    def test_short_words_untouched(self):
        self.assertIn("session", self.terms("session"))
        self.assertIn("cognito", self.terms("cognito"))

    def test_kind_words_are_intent_not_terms(self):
        self.assertNotIn("spec", self.terms("which specs touch X"))
        self.assertEqual(registry.kind_intent("which specs touch X"), {"spec"})
        self.assertEqual(registry.kind_intent("decisiones sobre X"), {"adr"})
        self.assertEqual(registry.kind_intent("who consumes X"), set())

class TestLoadDocs(RegistryCase):
    def test_layout_service_title_date(self):
        docs = {d.rel: d for d in load_docs(self.root, list(registry.REGISTRIES))}
        self.assertNotIn("service-catalog/.hidden/skip.md", docs)
        self.assertNotIn("investigation-registry/templates/ignored.md", docs)
        self.assertNotIn("spec-registry/consent-service/notes.md", docs)
        self.assertEqual(docs["service-catalog/leads-service.md"].service, "leads-service")
        self.assertEqual(docs["service-catalog/leads-service.md"].title, "leads-service")
        self.assertEqual(docs["service-catalog/leads-service.md"].date, "2026-06-07")
        self.assertEqual(docs["service-catalog/docs/leads-service/decisions.md"].service,
                         "leads-service")
        adr = docs["adr-registry/leads-service/PROJ-1-ADR-001-sns-fanout.md"]
        self.assertEqual((adr.service, adr.title, adr.date),
                         ("leads-service", "SNS fan-out for lead events", "2026-05-01"))


class TestSelect(RegistryCase):
    def loaded(self, res):
        return [d.rel for d, _ in res.loaded]

    def test_event_flow_crosses_services_without_filters(self):
        res = self.run_select("who consumes LeadCreated?", budget=20_000)
        self.assertEqual(res.mode, "ranked")
        for rel in ("service-catalog/marketing-service.md",
                    "service-catalog/consent-service.md"):
            self.assertIn(rel, self.loaded(res))
        self.assertNotIn("adr-registry/consent-service/PROJ-2-ADR-001-retries.md",
                         self.loaded(res))

    def test_named_service_boosts_but_does_not_filter(self):
        res = self.run_select("who consumes LeadCreated from leads-service?", budget=20_000)
        self.assertIn("service-catalog/marketing-service.md", self.loaded(res))

    def test_explicit_service_filters(self):
        q = parse_query(["service:consent-service retries"])
        res = select(q, load_docs(self.root, q.types), 100_000)
        self.assertTrue(res.scope)
        self.assertTrue(all(d.service == "consent-service" for d in res.scope))

    def test_large_docs_trimmed_to_matching_sections(self):
        res = self.run_select("who consumes LeadCreated?", budget=20_000)
        body = dict((d.rel, b) for d, b in res.loaded)["service-catalog/consent-service.md"]
        self.assertIn("LeadCreated", body)
        self.assertNotIn("Filler line 300", body)
        self.assertIn("[omitted sections", body)

    def test_budget_overflow_goes_to_also_matched(self):
        res = self.run_select("LeadCreated", budget=300)
        self.assertTrue(res.loaded)
        self.assertTrue(res.also)

    def test_whole_scope_fits_loads_everything(self):
        q = parse_query(["type:adr anything"])
        res = select(q, load_docs(self.root, q.types), 100_000)
        self.assertEqual(res.mode, "all")
        self.assertEqual(len(res.loaded), 2)

    def test_kind_word_boosts_that_registry(self):
        # both the catalog and the ADR mention LeadCreated; "decisions" favors the ADR
        res = self.run_select("decisions about LeadCreated", budget=300)
        self.assertEqual(res.loaded[0][0].kind, "adr")

    def test_open_questions_filter(self):
        res = self.run_select("which specs have open questions?")
        self.assertEqual(res.mode, "open-questions")
        self.assertEqual(self.loaded(res), ["spec-registry/leads-service/proj-3-spec.md"])
        body = res.loaded[0][1]
        self.assertIn("**#2** Who owns the TTL?", body)
        self.assertNotIn("**#1**", body)

    def test_no_match_is_reported_not_invented(self):
        res = self.run_select("rate limiting gateway")
        self.assertEqual(res.mode, "none")
        self.assertEqual(res.loaded, [])


class TestRender(RegistryCase):
    def test_index_always_and_citation_instruction(self):
        out = ask(["rate limiting gateway"], budget=4_000)
        self.assertIn("INDEX", out)
        self.assertIn("adr-registry/leads-service/PROJ-1-ADR-001-sns-fanout.md", out)
        self.assertIn("never invent", out)
        self.assertIn("none — no document matched", out)

    def test_investigations_oldest_first(self):
        out = ask(["type:investigation have we seen ReportToken reuse before?"],
                  budget=100_000)
        self.assertLess(out.index("FILE: investigation-registry/report-service/2026-03-01"),
                        out.index("FILE: investigation-registry/report-service/2026-08-01"))
        self.assertIn("oldest first", out)

    def test_tip_suggests_type_when_matches_concentrate(self):
        # "jobs" and "queue" only appear in catalogs
        out = ask(["jobs queue"], budget=20_000)
        self.assertIn("add type:catalog", out)

    def test_no_tip_when_type_given(self):
        out = ask(["type:catalog LeadCreated consumes"], budget=20_000)
        self.assertNotIn("tip:", out)

    def test_warning_rendered(self):
        self.assertIn("unknown type 'arch'", ask(["type:arch x"], budget=4_000))

    def test_empty_registry(self):
        with tempfile.TemporaryDirectory() as empty, \
                mock.patch.dict(os.environ, {"OPEN_SDD_DOC_HOME": empty}):
            out = ask(["anything"])
        self.assertIn("No documents found", out)
        self.assertIn("/doc-catalog", out)


class TestWiki(RegistryCase):
    def write_log(self, *stamps):
        wiki = self.root.parent / "wiki"
        wiki.mkdir()
        (wiki / "log.md").write_text(
            "# Activity Log\n\n" + "".join(f"## [{s}] ingest | x\n\n" for s in stamps))

    def test_no_wiki_no_wiki_line(self):
        self.assertNotIn("WIKI:", ask(["LeadCreated"], budget=4_000))

    def test_fresh_wiki_reported_without_warning(self):
        self.write_log("2020-01-01", "2999-01-01")      # newest entry wins
        out = ask(["LeadCreated"], budget=4_000)
        self.assertIn("last ingest: 2999-01-01", out)
        self.assertNotIn("wiki is behind", out)

    def test_stale_wiki_warns(self):
        self.write_log("2000-01-01")
        self.assertIn("The wiki is behind: 10 raw doc(s)", ask(["LeadCreated"], budget=4_000))

    def test_wiki_without_log_is_never_ingested(self):
        (self.root.parent / "wiki").mkdir()
        self.assertIn("last ingest: never", ask(["LeadCreated"], budget=4_000))


if __name__ == "__main__":
    unittest.main()
