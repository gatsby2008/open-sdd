# SDD — Key Concepts

Cross-cutting ideas that govern how the pipeline works in this project. Understand these concepts and the rest derives.

| Concept | Summary |
|---------|---------|
| **Pipeline instructions vs. rules snapshot** | Every `/f-*` command makes the LLM read `agent/PIPELINE.md` (protocol; detail on demand in `agent/REFERENCE.md`). `/f-start` snapshots the rules — the full text of `templates/rules.md` and `.opensdd/service-rules.md` (+ `.opensdd/rules/*.md`) — into `rules.json`, which downstream commands and `/f-handoff` read. Rules edited after `/f-start` need a new snapshot. |
| **`.specwork/` is transient** | All pipeline state lives in `.specwork/` — it is gitignored, created by `/f-start`, wiped by `/f-close`. It is working memory, not historical record. Never commit it. |
| **Open Questions gate progression** | Any unchecked `- [ ]` under `## Open Questions` in `spec.md` or `plan.md` blocks `/f-plan`, `/f-implement` and `/f-handoff`. BLOCKING OQs stop the pipeline. Resolve them via `/f-spec` (which also drafts the spec the first time) or direct spec edits. |
| **Plan-required gate** | A **high-risk** pipeline with no plan blocks `/f-implement` (`PLAN_REQUIRED`). A tier forced with `/f-spec --tier` wins over the automatic one, in both directions. Every other tier may skip `/f-plan`. |
| **Plan staleness gate** | If `plan.md` exists and is older than the stored `spec_write_timestamp` (from `state.json`), `/f-implement` blocks. The gate uses the **stored timestamp**, not filesystem mtime — because `/f-pause` stashes destroy mtimes. Re-run `/f-plan` or delete `plan.md` to fall back to inline discovery. |
| **Stack detection** | `detect_stack()` examines the project root for build files: `build.gradle`/`pom.xml` → `java`, `package.json` + a frontend framework → `frontend`, `package.json` alone → `node`, none → `unknown`. Every command switches heuristics based on stack. |
| **Triage / ticket classification** | `engine triage <slug>` (wrapped by `commands/triage.sh`, logic in `engine/triage.py`) scans `## Behavior` and `## Implementation Context` for high-risk keywords and estimates change scope (files touched, layers). Produces `path.json` with the tier: trivial / focused / standard / high-risk. Runs after `/f-spec` first draft, not during `/f-start`. Keywords can misfire (a negated "does not publish to Kafka" still matches), so `/f-spec --tier <tier> "<reason>"` forces the tier — stored as an `override` block, sticky; `--tier auto` drops it. |
| **Behavior ids and conformance** | Each `## Behavior` item has a stable id (`**B1**`, `**B2**`…); tests carry `spec: B<n>` tags. `/f-commit` lists Behaviors with no tagged test in the lines added on the branch — advisory, token-free, never blocks. |
| **High-risk auditor** | On high-risk pipelines `/f-commit` asks for `/f-code-review --auditor` (report-only) once per distinct diff; the verdict is stored with the diff's fingerprint in `_review/<slug>-audit.json`. Advisory: a FAIL never blocks. |
| **Rule promotion** | Before `/f-close` deletes the spec, it offers its Safe Constraints and resolved OQs as candidate rules (max 4); the approved ones are appended to `.claude/rules/*.md` with a provenance marker. Existing lines are never edited. |
| **Risk signals** | `detect_risk_signals()` is a **deterministic** regex match (not fuzzy triage) for 5 signals: `db-migration`, `auth-security`, `breaking-api`, `data-destructive`, `concurrency`. Used by `/f-auto` to decide whether to pause for optional test steps. `engine risk-signals <slug>` prints matching signals. |
| **`spec_write_timestamp`** | An epoch-seconds field in `state.json` bumped by every `/f-spec` write. Used by the plan staleness gate (compares against `plan.md` mtime). Exists because `/f-pause` stashes destroy filesystem mtimes. |
| **`SDD_NON_INTERACTIVE=1`** | Env var that suppresses bash prompts in `/f-start` (branch creation), `/f-commit` (message confirmation), and `/f-close` (skips rule promotion). Set by `/f-auto` for the non-interactive autopilot. Override manually with `SDD_NON_INTERACTIVE=1` to skip prompts in any command. |
| **Vibe coding** | `/f-commit`, `/f-mr`, `/f-code-review`, `/f-mr-review` and `/f-undo` work on **any branch with no pipeline setup**. No `.specwork/`, no spec, no plan needed. See [VIBE-CODING.md](vibe-coding.md). |
| **Quality gates** | `bash commands/check.sh` must pass before pushing (`/f-mr`); `/f-commit` does not run it. Failed checks block the push. open-sdd ships a stack-detecting default (`npm test`, `./gradlew check`, `mvn verify`, `pytest`, etc.). Projects override by placing their own `commands/check.sh`. |
| **Service-rules are a convention** | The team's rules live in `.claude/rules/*.md` (committed); `/f-start` syncs them into the personal, gitignored `.opensdd/service-rules.md`, which `/f-close` deletes. The file is not auto-discovered by the LLM — the pipeline instructions tell the model to load it. It is a pipeline convention, not a framework feature. |

---

**See also:**
- [open-sdd-architecture.md](open-sdd-architecture.md) — architectural overview
- [sdd-pipeline-cheatsheet.md](sdd-pipeline-cheatsheet.md) — command lookup
- [doc-adr-cheatsheet.md](doc-adr-cheatsheet.md) — service catalog + ADR commands
- [sdd-flashcards.md](sdd-flashcards.md) — deep-dive Q&A
- [VIBE-CODING.md](vibe-coding.md) — standalone commands without pipeline
