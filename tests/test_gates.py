import json
import subprocess
import tempfile
import os
import unittest
from pathlib import Path

from engine.gates import (
    resolve_slug,
    resolve_state_file,
    pipeline_branch_status,
    check_open_questions,
    check_plan_staleness,
    check_required_artifacts,
    check_branch_match,
    detect_stack,
    detect_risk_signals,
    check_spec_consistency,
    extract_reference_targets,
    ticket_from_branch,
    count_open_questions,
    get_resolved_oqs,
    format_staleness_error,
    audit_artifacts,
    SPECWORK,
)


class GatesTestCase(unittest.TestCase):

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name)
        self._old_cwd = os.getcwd()
        os.chdir(self.root)
        SPECWORK.mkdir(parents=True, exist_ok=True)

    def tearDown(self):
        os.chdir(self._old_cwd)
        self._tmp.cleanup()

    def _init_git_and_branch(self, branch: str):
        subprocess.run(["git", "init"], capture_output=True)
        subprocess.run(["git", "config", "user.email", "test@test.com"], capture_output=True)
        subprocess.run(["git", "config", "user.name", "Test"], capture_output=True)
        subprocess.run(["git", "commit", "--allow-empty", "-m", "initial"], capture_output=True)
        subprocess.run(["git", "checkout", "-b", branch], capture_output=True)

    # --- resolve_slug ---

    def test_resolve_slug_from_state_file(self):
        self._init_git_and_branch("feature/my-feature")
        (SPECWORK / "_state").mkdir(parents=True, exist_ok=True)
        state = {"id": "my-feature", "branch": "feature/my-feature"}
        (SPECWORK / "_state" / "my-feature-state.json").write_text(
            json.dumps(state), encoding="utf-8")
        slug = resolve_slug()
        self.assertEqual(slug, "my-feature")

    def test_resolve_slug_fallback_from_branch(self):
        self._init_git_and_branch("feature/my-fallback")
        slug = resolve_slug()
        self.assertEqual(slug, "my-fallback")

    def test_resolve_slug_without_git_returns_none(self):
        slug = resolve_slug()
        self.assertIsNone(slug)

    # --- resolve_state_file ---

    def test_resolve_state_file_by_slug(self):
        self._init_git_and_branch("main")
        (SPECWORK / "_state").mkdir(parents=True, exist_ok=True)
        (SPECWORK / "_state" / "slug-a-state.json").write_text(
            json.dumps({"id": "slug-a", "branch": "main"}), encoding="utf-8")
        result = resolve_state_file()
        self.assertIsNotNone(result)
        self.assertTrue(str(result).endswith("slug-a-state.json"))

    def test_resolve_state_file_ignores_other_branch_state(self):
        # Regression: .specwork/ is gitignored and survives `git checkout`, so
        # it commonly still holds a *different* branch's leftover pipeline
        # state. resolve_state_file() must not treat that as this branch's
        # active pipeline just because it's the only (or first) file present.
        self._init_git_and_branch("feature/my-feature")
        (SPECWORK / "_state").mkdir(parents=True, exist_ok=True)
        (SPECWORK / "_state" / "other-ticket-state.json").write_text(
            json.dumps({"id": "other-ticket", "branch": "feature/other-ticket"}),
            encoding="utf-8")
        result = resolve_state_file()
        self.assertIsNone(result)

    def test_resolve_state_file_picks_matching_file_among_several(self):
        # Regression: with multiple state files present, the one for the
        # current branch must be found regardless of sort/glob order.
        self._init_git_and_branch("feature/my-feature")
        (SPECWORK / "_state").mkdir(parents=True, exist_ok=True)
        (SPECWORK / "_state" / "a-earlier-alphabetically-state.json").write_text(
            json.dumps({"id": "a-earlier-alphabetically", "branch": "feature/other-ticket"}),
            encoding="utf-8")
        (SPECWORK / "_state" / "z-later-alphabetically-state.json").write_text(
            json.dumps({"id": "z-later-alphabetically", "branch": "feature/my-feature"}),
            encoding="utf-8")
        result = resolve_state_file()
        self.assertIsNotNone(result)
        self.assertTrue(str(result).endswith("z-later-alphabetically-state.json"))

    # --- pipeline_branch_status ---

    def test_pipeline_branch_status_no_pipeline_at_all(self):
        self._init_git_and_branch("feature/anything")
        status = pipeline_branch_status("feature/anything")
        self.assertEqual(status, {
            "current_branch": "feature/anything",
            "has_any_pipeline": False,
            "owns_pipeline": False,
            "slug": "",
            "recorded_branch": "",
            "recorded_base_branch": "",
            "is_base_branch": False,
        })

    def test_pipeline_branch_status_owns_pipeline(self):
        self._init_git_and_branch("feature/ZZZ")
        (SPECWORK / "_state").mkdir(parents=True, exist_ok=True)
        (SPECWORK / "_state" / "zzz-state.json").write_text(
            json.dumps({"id": "zzz", "branch": "feature/ZZZ", "base_branch": "main"}),
            encoding="utf-8")
        status = pipeline_branch_status("feature/ZZZ")
        self.assertTrue(status["owns_pipeline"])
        self.assertEqual(status["slug"], "zzz")
        self.assertEqual(status["recorded_branch"], "feature/ZZZ")
        self.assertEqual(status["recorded_base_branch"], "main")
        self.assertFalse(status["is_base_branch"])

    def test_pipeline_branch_status_is_base_branch(self):
        # The "MR merged, back on main, now cleaning up" case /f-close is
        # meant to allow without a hard-stop.
        self._init_git_and_branch("main")
        (SPECWORK / "_state").mkdir(parents=True, exist_ok=True)
        (SPECWORK / "_state" / "zzz-state.json").write_text(
            json.dumps({"id": "zzz", "branch": "feature/ZZZ", "base_branch": "main"}),
            encoding="utf-8")
        status = pipeline_branch_status("main")
        self.assertFalse(status["owns_pipeline"])
        self.assertTrue(status["is_base_branch"])
        self.assertEqual(status["slug"], "zzz")
        self.assertEqual(status["recorded_branch"], "feature/ZZZ")

    def test_pipeline_branch_status_unrelated_third_branch(self):
        # Regression for the /f-close data-loss bug: a brand-new branch for
        # unrelated work, with only another branch's leftover pipeline on
        # disk. Neither owns_pipeline nor is_base_branch should be true.
        self._init_git_and_branch("feature/mybranch")
        (SPECWORK / "_state").mkdir(parents=True, exist_ok=True)
        (SPECWORK / "_state" / "zzz-state.json").write_text(
            json.dumps({"id": "zzz", "branch": "feature/ZZZ", "base_branch": "main"}),
            encoding="utf-8")
        status = pipeline_branch_status("feature/mybranch")
        self.assertFalse(status["owns_pipeline"])
        self.assertFalse(status["is_base_branch"])
        self.assertEqual(status["slug"], "zzz")
        self.assertEqual(status["recorded_branch"], "feature/ZZZ")

    def test_pipeline_branch_status_defaults_to_current_branch(self):
        self._init_git_and_branch("feature/ZZZ")
        (SPECWORK / "_state").mkdir(parents=True, exist_ok=True)
        (SPECWORK / "_state" / "zzz-state.json").write_text(
            json.dumps({"id": "zzz", "branch": "feature/ZZZ"}), encoding="utf-8")
        status = pipeline_branch_status()  # no branch arg -> _current_branch()
        self.assertTrue(status["owns_pipeline"])
        self.assertEqual(status["slug"], "zzz")

    # --- check_open_questions ---

    def _write_spec(self, slug: str, body: str):
        (SPECWORK / "_spec").mkdir(parents=True, exist_ok=True)
        (SPECWORK / "_spec" / f"{slug}-spec.md").write_text(body, encoding="utf-8")

    def test_no_unresolved_oqs_passes(self):
        self._write_spec("clean", """\
# clean

## Open Questions

- [x] This is resolved
""")
        blockers = check_open_questions("clean")
        self.assertEqual(blockers, [])

    def test_unresolved_oqs_are_detected(self):
        self._write_spec("oqs", """\
# oqs

## Open Questions

- [ ] **#1** What db should we use?
- [ ] **#2** How to handle retries?
""")
        blockers = check_open_questions("oqs")
        self.assertEqual(len(blockers), 1)
        path, items = blockers[0]
        self.assertIn("oqs-spec.md", path)
        self.assertEqual(len(items), 2)

    def test_missing_spec_returns_empty_list(self):
        blockers = check_open_questions("nonexistent")
        self.assertEqual(blockers, [])

    def test_unresolved_oqs_in_plan_also_detected(self):
        self._write_spec("spec-ok", "# spec-ok\n\n## Open Questions\n\n- [x] done\n")
        (SPECWORK / "_plan").mkdir(parents=True, exist_ok=True)
        (SPECWORK / "_plan" / "spec-ok-plan.md").write_text(
            "# plan\n\n## Open Questions\n\n- [ ] Still open\n", encoding="utf-8")
        blockers = check_open_questions("spec-ok")
        self.assertEqual(len(blockers), 1)

    # --- check_plan_staleness ---

    def test_no_plan_is_not_stale(self):
        self.assertFalse(check_plan_staleness("noplan"))

    def test_plan_newer_than_spec_is_not_stale(self):
        (SPECWORK / "_plan").mkdir(parents=True, exist_ok=True)
        (SPECWORK / "_state").mkdir(parents=True, exist_ok=True)
        plan = SPECWORK / "_plan" / "mytest-plan.md"
        plan.write_text("plan", encoding="utf-8")
        state = {
            "spec_write_timestamp": int(plan.stat().st_mtime) - 100,
        }
        (SPECWORK / "_state" / "mytest-state.json").write_text(
            json.dumps(state), encoding="utf-8")
        self.assertFalse(check_plan_staleness("mytest"))

    def test_plan_older_than_spec_is_stale(self):
        (SPECWORK / "_plan").mkdir(parents=True, exist_ok=True)
        (SPECWORK / "_state").mkdir(parents=True, exist_ok=True)
        plan = SPECWORK / "_plan" / "stale-plan.md"
        plan.write_text("plan", encoding="utf-8")
        state = {
            "spec_write_timestamp": int(plan.stat().st_mtime) + 100,
        }
        (SPECWORK / "_state" / "stale-state.json").write_text(
            json.dumps(state), encoding="utf-8")
        self.assertTrue(check_plan_staleness("stale"))

    # --- format_staleness_error ---

    def test_format_staleness_error_empty_when_fresh(self):
        (SPECWORK / "_plan").mkdir(parents=True, exist_ok=True)
        (SPECWORK / "_state").mkdir(parents=True, exist_ok=True)
        plan = SPECWORK / "_plan" / "fresh-plan.md"
        plan.write_text("plan", encoding="utf-8")
        (SPECWORK / "_state" / "fresh-state.json").write_text(
            json.dumps({"spec_write_timestamp": int(plan.stat().st_mtime) - 100}),
            encoding="utf-8")
        self.assertEqual(format_staleness_error("fresh"), "")

    def test_format_staleness_error_message_when_stale(self):
        (SPECWORK / "_plan").mkdir(parents=True, exist_ok=True)
        (SPECWORK / "_state").mkdir(parents=True, exist_ok=True)
        plan = SPECWORK / "_plan" / "stalemsg-plan.md"
        plan.write_text("plan", encoding="utf-8")
        (SPECWORK / "_state" / "stalemsg-state.json").write_text(
            json.dumps({"spec_write_timestamp": int(plan.stat().st_mtime) + 100}),
            encoding="utf-8")
        msg = format_staleness_error("stalemsg")
        self.assertIn("Plan is stale", msg)
        self.assertIn("stalemsg-plan.md", msg)

    # --- extract_reference_targets ---

    def test_extract_reference_targets_finds_destructive_symbols(self):
        (SPECWORK / "_spec").mkdir(parents=True, exist_ok=True)
        spec = SPECWORK / "_spec" / "refs-spec.md"
        spec.write_text(
            "## Behavior\n\nRemove the `LegacyService` class and delete `OldMapper`.\n",
            encoding="utf-8")
        symbols = extract_reference_targets(spec)
        self.assertIn("LegacyService", symbols)
        self.assertIn("OldMapper", symbols)

    def test_extract_reference_targets_excludes_negated_and_safe_constraints(self):
        (SPECWORK / "_spec").mkdir(parents=True, exist_ok=True)
        spec = SPECWORK / "_spec" / "refs2-spec.md"
        spec.write_text(
            "## Behavior\n\nDo NOT remove `KeepThis`.\n\n"
            "## Safe Constraints\n\nDelete `SafeOnly` is mentioned here.\n",
            encoding="utf-8")
        symbols = extract_reference_targets(spec)
        self.assertNotIn("KeepThis", symbols)
        self.assertNotIn("SafeOnly", symbols)

    def test_extract_reference_targets_missing_spec(self):
        self.assertEqual(extract_reference_targets(Path("nope.md")), [])

    # --- check_required_artifacts ---

    def test_all_required_present(self):
        (SPECWORK / "_state").mkdir(parents=True, exist_ok=True)
        (SPECWORK / "_spec").mkdir(parents=True, exist_ok=True)
        for f in ["_state/myart-state.json", "_state/myart-rules.json", "_spec/myart-spec.md"]:
            (SPECWORK / f).write_text("{}", encoding="utf-8")
        missing = check_required_artifacts("myart")
        self.assertEqual(missing, [])

    def test_missing_artifacts_reported(self):
        missing = check_required_artifacts("noart")
        self.assertEqual(len(missing), 3)

    # --- check_branch_match ---

    def test_branch_match_success(self):
        self._init_git_and_branch("feature/match")
        (SPECWORK / "_state").mkdir(parents=True, exist_ok=True)
        state = {"id": "match", "branch": "feature/match"}
        (SPECWORK / "_state" / "match-state.json").write_text(
            json.dumps(state), encoding="utf-8")
        result = check_branch_match("match")
        self.assertIsNone(result)

    def test_branch_match_mismatch(self):
        self._init_git_and_branch("feature/current")
        (SPECWORK / "_state").mkdir(parents=True, exist_ok=True)
        state = {"id": "mismatch", "branch": "feature/other"}
        (SPECWORK / "_state" / "mismatch-state.json").write_text(
            json.dumps(state), encoding="utf-8")
        result = check_branch_match("mismatch")
        self.assertIsNotNone(result)
        self.assertIn("BRANCH_MISMATCH", result)

    def test_branch_match_no_state_returns_none(self):
        result = check_branch_match("missing")
        self.assertIsNone(result)

    # --- detect_stack ---

    def test_detect_stack_java(self):
        Path("build.gradle").write_text("", encoding="utf-8")
        self.assertEqual(detect_stack(), "java")

    def test_detect_stack_java_kts(self):
        Path("build.gradle.kts").write_text("", encoding="utf-8")
        self.assertEqual(detect_stack(), "java")

    def test_detect_stack_node(self):
        Path("package.json").write_text("{}", encoding="utf-8")
        self.assertEqual(detect_stack(), "node")

    def test_detect_stack_frontend_by_config(self):
        # A frontend framework config file (next to package.json) → "frontend".
        Path("package.json").write_text("{}", encoding="utf-8")
        Path("vite.config.ts").write_text("", encoding="utf-8")
        self.assertEqual(detect_stack(), "frontend")

    def test_detect_stack_frontend_by_dependency(self):
        # No config file, but a frontend framework dependency → "frontend".
        Path("package.json").write_text(
            '{"dependencies": {"react": "^18.0.0"}}', encoding="utf-8"
        )
        self.assertEqual(detect_stack(), "frontend")

    def test_detect_stack_node_backend_stays_node(self):
        # package.json with only backend deps (no frontend config/framework) → "node".
        Path("package.json").write_text(
            '{"dependencies": {"express": "^4.18.0"}}', encoding="utf-8"
        )
        self.assertEqual(detect_stack(), "node")

    def test_detect_stack_java_wins_over_package_json(self):
        # Polyglot repo (build.gradle + package.json) resolves to java — java is
        # checked first. Guards the detection precedence.
        Path("build.gradle").write_text("", encoding="utf-8")
        Path("package.json").write_text(
            '{"dependencies": {"react": "^18.0.0"}}', encoding="utf-8"
        )
        self.assertEqual(detect_stack(), "java")

    def test_detect_stack_unknown(self):
        self.assertEqual(detect_stack(), "unknown")

    # --- detect_risk_signals ---

    def test_risk_signals_none(self):
        spec = SPECWORK / "_spec" / "safe-spec.md"
        (SPECWORK / "_spec").mkdir(parents=True, exist_ok=True)
        spec.write_text("# safe\n\nSimple rename.", encoding="utf-8")
        signals = detect_risk_signals(spec)
        self.assertEqual(signals, {})

    def test_risk_signals_db_migration(self):
        spec = SPECWORK / "_spec" / "migrate-spec.md"
        (SPECWORK / "_spec").mkdir(parents=True, exist_ok=True)
        spec.write_text("# migrate\n\nAdd a Flyway migration for the new column.", encoding="utf-8")
        signals = detect_risk_signals(spec)
        self.assertIn("db-migration", signals)
        self.assertIn("migration", signals["db-migration"])
        self.assertIn("flyway", signals["db-migration"])

    def test_risk_signals_auth(self):
        spec = SPECWORK / "_spec" / "auth-spec.md"
        (SPECWORK / "_spec").mkdir(parents=True, exist_ok=True)
        spec.write_text("# auth\n\nJWT token validation in SecurityConfig.", encoding="utf-8")
        signals = detect_risk_signals(spec)
        self.assertIn("auth-security", signals)

    def test_risk_signals_missing_spec(self):
        signals = detect_risk_signals(Path("nonexistent.md"))
        self.assertEqual(signals, {})

    def test_risk_signals_frontend_routing(self):
        spec = SPECWORK / "_spec" / "routing-spec.md"
        (SPECWORK / "_spec").mkdir(parents=True, exist_ok=True)
        spec.write_text("# routing\n\nRestructure navigation with react-router nested routes.", encoding="utf-8")
        signals = detect_risk_signals(spec)
        self.assertIn("routing", signals)

    def test_risk_signals_frontend_data_fetching(self):
        spec = SPECWORK / "_spec" / "fetch-spec.md"
        (SPECWORK / "_spec").mkdir(parents=True, exist_ok=True)
        spec.write_text("# fetch\n\nReplace manual fetches with react-query useQuery hooks.", encoding="utf-8")
        signals = detect_risk_signals(spec)
        self.assertIn("data-fetching", signals)

    def test_risk_signals_frontend_component_api(self):
        spec = SPECWORK / "_spec" / "comp-spec.md"
        (SPECWORK / "_spec").mkdir(parents=True, exist_ok=True)
        spec.write_text("# comp\n\nBreaking change in component: rename prop onClose to onDismiss.", encoding="utf-8")
        signals = detect_risk_signals(spec)
        self.assertIn("component-api", signals)

    def test_risk_signals_frontend_state_management(self):
        spec = SPECWORK / "_spec" / "state-spec.md"
        (SPECWORK / "_spec").mkdir(parents=True, exist_ok=True)
        spec.write_text("# state\n\nMigrate from Redux to Zustand for the cart store.", encoding="utf-8")
        signals = detect_risk_signals(spec)
        self.assertIn("state-management", signals)

    def test_risk_signals_frontend_accessibility(self):
        spec = SPECWORK / "_spec" / "a11y-spec.md"
        (SPECWORK / "_spec").mkdir(parents=True, exist_ok=True)
        spec.write_text("# a11y\n\nAdd aria-label and keyboard navigation for screen readers.", encoding="utf-8")
        signals = detect_risk_signals(spec)
        self.assertIn("accessibility", signals)

    def test_risk_signals_frontend_ui_migration(self):
        spec = SPECWORK / "_spec" / "ui-spec.md"
        (SPECWORK / "_spec").mkdir(parents=True, exist_ok=True)
        spec.write_text("# ui\n\nDesign system update: migrate from Bootstrap to Tailwind.", encoding="utf-8")
        signals = detect_risk_signals(spec)
        self.assertIn("ui-migration", signals)

    def test_risk_signals_no_frontend_in_backend_spec(self):
        spec = SPECWORK / "_spec" / "backend-spec.md"
        (SPECWORK / "_spec").mkdir(parents=True, exist_ok=True)
        spec.write_text("# backend\n\nAdd a repository method to fetch orders by status.", encoding="utf-8")
        signals = detect_risk_signals(spec)
        for fe in ("component-api", "state-management", "accessibility", "routing", "data-fetching", "ui-migration"):
            self.assertNotIn(fe, signals)

    # --- check_spec_consistency ---

    def test_no_contradictions(self):
        spec = SPECWORK / "_spec" / "clean-spec.md"
        (SPECWORK / "_spec").mkdir(parents=True, exist_ok=True)
        spec.write_text(
            "# clean\n\nThis is a simple feature with no contradictions.\n\nJust a rename.\n",
            encoding="utf-8")
        flagged = check_spec_consistency(spec)
        self.assertEqual(flagged, [])

    def test_detects_idempotent_with_side_effect(self):
        spec = SPECWORK / "_spec" / "contra-spec.md"
        (SPECWORK / "_spec").mkdir(parents=True, exist_ok=True)
        spec.write_text(
            "# contra\n\n## Behavior\n\nThe endpoint is idempotent.\n\n"
            "It must log on each invocation.\n",
            encoding="utf-8")
        flagged = check_spec_consistency(spec)
        self.assertIn("idempotent + per-call side effect", flagged)

    def test_missing_spec_returns_empty(self):
        flagged = check_spec_consistency(Path("missing.md"))
        self.assertEqual(flagged, [])

    # --- ticket_from_branch ---

    def test_ticket_strict_jira(self):
        self.assertEqual(ticket_from_branch("feature/IR-70"), ("IR-70", "jira"))
        self.assertEqual(ticket_from_branch("feature/MYYES-1234-x"), ("MYYES-1234", "jira"))

    def test_ticket_loose_is_freetext(self):
        self.assertEqual(ticket_from_branch("feature/IR-70.1"), ("IR-70.1", "freetext"))

    def test_ticket_none(self):
        self.assertEqual(ticket_from_branch("feature/add-thing"), ("", "freetext"))

    # --- count / resolved open questions ---

    def test_count_open_questions(self):
        self._write_spec("oq", (
            "# oq\n\n## Open Questions\n\n"
            "- [ ] Q1?\n- [x] Q2? — yes\n- [X] Q3 no sep\n\n"
            "## Behavior\n\n- [ ] not an OQ\n"
        ))
        self.assertEqual(count_open_questions("oq"), (1, 2))

    def test_count_open_questions_missing_spec(self):
        self.assertEqual(count_open_questions("nope"), (0, 0))

    def test_get_resolved_oqs(self):
        self._write_spec("oq", (
            "# oq\n\n## Open Questions\n\n- [ ] Q1?\n- [x] Q2? — do it this way\n"
        ))
        resolved = get_resolved_oqs("oq")
        self.assertEqual(resolved["Q2?"], "do it this way")
        self.assertNotIn("Q1?", resolved)

    # --- audit_artifacts ---

    def test_audit_artifacts(self):
        self._write_spec("demo", "# demo\n")
        audit = audit_artifacts("demo")
        self.assertTrue(audit["spec_file"]["exists"])
        self.assertIsNotNone(audit["spec_file"]["mtime"])
        self.assertFalse(audit["plan_file"]["exists"])
        self.assertIn("state_file", audit)


if __name__ == "__main__":
    unittest.main()
