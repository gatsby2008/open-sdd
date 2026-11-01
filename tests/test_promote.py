import os
import shutil
import tempfile
import unittest

from engine import promote


RULES = """# Service Rules — leads

## Business Invariants

- Hand-written rule one.
- Hand-written rule two,
  continued on an indented line.

> **Implementation note:** rationale written by a human.

## Architecture Constraints

- Constructor injection only.
"""

DATE = "2026-10-31"


class TestInsertRules(unittest.TestCase):
    def test_appends_after_last_bullet_with_provenance(self):
        new = promote.insert_rules(RULES, [{"section": "Business Invariants", "rule": "Leads are idempotent per applicationId."}], "lead-dedupe", DATE)
        lines = new.splitlines()
        i = lines.index("  continued on an indented line.")
        self.assertEqual(lines[i + 1], "- Leads are idempotent per applicationId. _(from spec lead-dedupe, 2026-10-31)_")
        self.assertTrue(promote.only_insertions(RULES, new))

    def test_section_match_ignores_case_and_hashes(self):
        new = promote.insert_rules(RULES, [{"section": "## architecture constraints", "rule": "No field injection."}], "s", DATE)
        self.assertTrue(new.rstrip().endswith("- No field injection. _(from spec s, 2026-10-31)_"))

    def test_missing_section_is_created_at_end(self):
        new = promote.insert_rules(RULES, [{"section": "Fallback and Idempotency", "rule": "Retry at most 3 times."}], "s", DATE)
        self.assertTrue(new.endswith("## Fallback and Idempotency\n\n- Retry at most 3 times. _(from spec s, 2026-10-31)_\n"))
        self.assertTrue(promote.only_insertions(RULES, new))

    def test_crlf_is_preserved(self):
        crlf = RULES.replace("\n", "\r\n")
        new = promote.insert_rules(crlf, [{"section": "Business Invariants", "rule": "x"}], "s", DATE)
        self.assertNotIn("\n", new.replace("\r\n", ""))


class TestOnlyInsertions(unittest.TestCase):
    def test_detects_modified_line(self):
        self.assertFalse(promote.only_insertions(RULES, RULES.replace("rule one", "rule 1")))

    def test_detects_deleted_line(self):
        self.assertFalse(promote.only_insertions(RULES, RULES.replace("- Constructor injection only.\n", "")))


class TestApply(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.path = os.path.join(self.tmp, "service-rules.md")

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def test_hand_written_bytes_survive(self):
        with open(self.path, "w") as f:
            f.write(RULES)
        count = promote.apply(self.path, "s", [{"section": "Business Invariants", "rule": "r"}], date=DATE)
        self.assertEqual(count, 1)
        with open(self.path) as f:
            self.assertTrue(promote.only_insertions(RULES, f.read()))

    def test_rejected_write_leaves_file_untouched(self):
        with open(self.path, "w") as f:
            f.write(RULES)
        original = promote.insert_rules
        promote.insert_rules = lambda text, *a, **k: text.replace("rule one", "rewritten")
        try:
            with self.assertRaises(ValueError):
                promote.apply(self.path, "s", [{"section": "Business Invariants", "rule": "r"}], date=DATE)
        finally:
            promote.insert_rules = original
        with open(self.path) as f:
            self.assertEqual(f.read(), RULES)

    def test_creates_missing_file(self):
        path = os.path.join(self.tmp, "rules", "leads.md")
        promote.apply(path, "s", [{"section": "Business Invariants", "rule": "r"}], date=DATE)
        with open(path) as f:
            self.assertEqual(f.read(), "## Business Invariants\n\n- r _(from spec s, 2026-10-31)_\n")

    def test_no_entries_writes_nothing(self):
        self.assertEqual(promote.apply(self.path, "s", [{"section": "X", "rule": "  "}]), 0)
        self.assertFalse(os.path.exists(self.path))


class TestApplyAll(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.old_cwd = os.getcwd()
        os.chdir(self.tmp)
        os.makedirs(".claude/rules")
        with open(".claude/rules/leads.md", "w") as f:
            f.write(RULES)

    def tearDown(self):
        os.chdir(self.old_cwd)
        shutil.rmtree(self.tmp)

    def test_groups_by_file_and_defaults_to_service_rules(self):
        written = promote.apply_all("s", [
            {"file": ".claude/rules/leads.md", "section": "Business Invariants", "rule": "a"},
            {"section": "Business Invariants", "rule": "b"},
        ], date=DATE)
        self.assertEqual(written, {".claude/rules/leads.md": 1, ".claude/rules/service-rules.md": 1})
        with open(".claude/rules/service-rules.md") as f:
            self.assertIn("- b _(from spec s, 2026-10-31)_", f.read())

    def test_dry_run_writes_nothing(self):
        written = promote.apply_all("s", [{"section": "X", "rule": "r"}], dry_run=True, date=DATE)
        self.assertEqual(written, {".claude/rules/service-rules.md": 1})
        self.assertFalse(os.path.exists(".claude/rules/service-rules.md"))

    def test_targets_outside_claude_rules_are_refused_before_any_write(self):
        for target in (".opensdd/service-rules.md", "docs/rules.md", ".claude/rules/x.txt"):
            with self.assertRaises(ValueError):
                promote.apply_all("s", [
                    {"file": ".claude/rules/leads.md", "section": "Business Invariants", "rule": "a"},
                    {"file": target, "section": "S", "rule": "r"},
                ], date=DATE)
        with open(".claude/rules/leads.md") as f:
            self.assertEqual(f.read(), RULES)


if __name__ == "__main__":
    unittest.main()
