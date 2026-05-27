import os
import tempfile
import unittest
from pathlib import Path


class TmpArtifactCase(unittest.TestCase):
    """Creates a temp .specwork/ tree with a spec and a plan."""

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp = Path(self._tmp.name)
        (self.tmp / "_spec").mkdir(parents=True)
        (self.tmp / "_plan").mkdir(parents=True)
        (self.tmp / "_state").mkdir(parents=True)
        self.addCleanup(self._tmp.cleanup)

    def _write_spec(self, slug: str, body: str) -> Path:
        p = self.tmp / "_spec" / f"{slug}-spec.md"
        p.write_text(body)
        return p

    def _write_plan(self, slug: str, body: str) -> Path:
        p = self.tmp / "_plan" / f"{slug}-plan.md"
        p.write_text(body)
        return p

    def _abs_of(self, rel: str) -> str:
        """$(cd "$(dirname "$REL")" && pwd)/$(basename "$REL")"""
        p = Path(rel)
        if not p.is_absolute():
            p = self.tmp / p
        return str(p.resolve())

    def _oq_line(self, path: Path) -> int | None:
        """grep -n '^## Open Questions' <file> | head -1 | cut -d: -f1"""
        for i, line in enumerate(path.read_text().splitlines(), start=1):
            if line.startswith("## Open Questions"):
                return i
        return None

    def _clickable(self, abs_path: str, oq_line: int | None) -> str:
        """Template: `<ABS>${OQ_LINE:+:$OQ_LINE}`"""
        suffix = f":{oq_line}" if oq_line is not None else ""
        return f"`{abs_path}{suffix}`"


class TestSpecPathClickable(TmpArtifactCase):
    """Spec path: absoluto + backtick + :line apuntando a ## Open Questions."""

    def test_spec_path_is_absolute(self):
        rel = ".specwork/_spec/my-slug-spec.md"
        abs_path = self._abs_of(rel)
        self.assertTrue(abs_path.startswith("/"))
        self.assertTrue(abs_path.endswith("my-slug-spec.md"))

    def test_spec_oq_line_found(self):
        spec = self._write_spec("s", (
            "# s\n\n## Summary\n\n## Open Questions\n- [ ] #1 test\n"
        ))
        line = self._oq_line(spec)
        self.assertEqual(line, 5)

    def test_spec_oq_line_missing(self):
        spec = self._write_spec("s", "# s\n\n## Summary\n")
        line = self._oq_line(spec)
        self.assertIsNone(line)

    def test_clickable_with_oq(self):
        rendered = self._clickable("/abs/path/spec.md", 42)
        self.assertEqual(rendered, "`/abs/path/spec.md:42`")
        self.assertFalse(rendered.endswith("."))
        self.assertFalse(rendered.endswith(":"))

    def test_clickable_without_oq(self):
        rendered = self._clickable("/abs/path/spec.md", None)
        self.assertEqual(rendered, "`/abs/path/spec.md`")

    def test_full_spec_output_format(self):
        slug = "my-feature"
        spec = self._write_spec(slug, (
            "# my-feature\n"
            "## Summary\n"
            "Do the thing.\n"
            "## Open Questions\n"
            "- [ ] #1 What color?\n"
        ))
        abs_path = str(spec.resolve())
        oq_line = self._oq_line(spec)
        rendered = self._clickable(abs_path, oq_line)

        expected = f"`{abs_path}:4`"
        self.assertEqual(rendered, expected)
        summary_line = f"  Spec:    {rendered}"
        self.assertIn(abs_path, summary_line)
        self.assertIn(":4", summary_line)


class TestPlanPathClickable(TmpArtifactCase):
    """Plan path: mismo formato que spec."""

    def test_plan_oq_line_found(self):
        plan = self._write_plan("s", (
            "# Plan\n\n## Target Files\n\n## Open Questions\n- [ ] #1 Which class?\n"
        ))
        line = self._oq_line(plan)
        self.assertEqual(line, 5)

    def test_plan_path_absolute_with_oq(self):
        plan = self._write_plan("p", (
            "## Open Questions\n- [ ] #1 test\n"
        ))
        abs_path = str(plan.resolve())
        oq_line = self._oq_line(plan)
        rendered = f"`{abs_path}:{oq_line}`"
        self.assertEqual(rendered, f"`{abs_path}:1`")

    def test_plan_missing_file_omits_line(self):
        plan_path = self.tmp / "_plan" / "nonexistent-plan.md"
        self.assertFalse(plan_path.exists())
        rendered = ""
        if plan_path.exists():
            rendered = f"`{str(plan_path.resolve())}`"
        self.assertEqual(rendered, "")


class TestHandoffPathClickable(TmpArtifactCase):
    """Handoff paths: absolutos + backtick, sin :line (no tienen OQ)."""

    def test_handoff_path_absolute(self):
        md_rel = ".specwork/_handoff/s-execution-pack.md"
        json_rel = ".specwork/_handoff/s-execution-pack.json"
        for rel in (md_rel, json_rel):
            abs_path = self._abs_of(rel)
            self.assertTrue(abs_path.startswith("/"))
            self.assertIn("_handoff", abs_path)

    def test_handoff_rendered_without_line(self):
        md = f"`{self._abs_of('.specwork/_handoff/s-execution-pack.md')}`"
        json = f"`{self._abs_of('.specwork/_handoff/s-execution-pack.json')}`"
        self.assertNotIn(":", md)
        self.assertNotIn(":", json)


class TestGateAbortOutput(TmpArtifactCase):
    """Formato del mensaje de aborto de f-implement con paths clickeables."""

    def test_gate_format_spec_only(self):
        spec = self._write_spec("s", (
            "## Open Questions\n- [ ] #1 unresolved\n"
        ))
        abs_spec = str(spec.resolve())
        oq = 3
        line = f"  - `{abs_spec}:{oq}`  (1 item)"
        self.assertIn(abs_spec, line)
        self.assertIn(":3", line)

    def test_gate_format_spec_and_plan(self):
        spec = self._write_spec("s", (
            "## Open Questions\n- [ ] #1 unresolved\n"
        ))
        plan = self._write_plan("s", (
            "## Open Questions\n- [ ] #1 plan issue\n"
        ))
        abs_spec = str(spec.resolve())
        abs_plan = str(plan.resolve())
        output = (
            "✗ Cannot implement.\n\n"
            "Unresolved Open Questions:\n"
            f"  - `{abs_spec}:3`  (1 item)\n"
            f"  - `{abs_plan}:3`  (1 item)\n\n"
            "Resolve them in the respective file, then re-run /f-implement.\n"
        )
        self.assertIn(abs_spec, output)
        self.assertIn(abs_plan, output)
        self.assertIn(":3", output)
        self.assertIn("Cannot implement", output)


if __name__ == "__main__":
    unittest.main()
