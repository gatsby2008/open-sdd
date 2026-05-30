# SDD — Key Concepts

Cross-cutting ideas that govern how the pipeline works in this project. Understand these 9 concepts and the rest derives.

| Concept | Summary |
|---------|---------|
| **Pipeline instructions as dual-source** | The LLM loads the pipeline instructions as system instructions (full prose, section semantics). `/f-start` compiles the project's pipeline instructions + `.opensdd/service-rules.md` into `rules.json` via `engine/gates.py` (lossy: only top-level bullets, capped at 20, no sub-bullets). Two different consumers, one source file. |
| **`.specwork/` is transient** | All pipeline state lives in `.specwork/` — it is gitignored, created by `/f-start`, wiped by `/f-close`. It is working memory, not historical record. Never commit it. |
| **Open Questions gate progression** | Any unchecked `- [ ]` under `## Open Questions` in `spec.md` or `plan.md` blocks `/f-implement` and downstream commands. BLOCKING OQs stop the pipeline. Resolve them via `/f-spec` (which also drafts the spec the first time) or direct spec edits. |
| **Plan staleness gate** | If `plan.md` exists and is older than the stored `spec_write_timestamp` (from `state.json`), `/f-implement` blocks. The gate uses the **stored timestamp**, not filesystem mtime — because `/f-pause` stashes destroy mtimes. Re-run `/f-plan` or delete `plan.md` to fall back to inline discovery. |
| **Stack detection** | `detect_stack()` examines the project root for build files: `build.gradle`/`pom.xml` → `java`, `package.json` → `node`, neither → `unknown`. Every command switches heuristics based on stack. |
| **Triage / ticket classification** | `engine triage <slug>` scans the spec for high-risk keywords (auth, migration, concurrency, breaking API) and estimates change scope (files touched, layers). Produces `path.json` with complexity tier: trivial / focused / standard / high-risk. Runs after `/f-spec` first draft, not during `/f-start`. |
| **Risk signals** | `detect_risk_signals()` is a **deterministic** regex match (not fuzzy triage) for 5 signals: `db-migration`, `auth-security`, `breaking-api`, `data-destructive`, `concurrency`. Used by `/f-auto` to decide whether to pause for optional test steps. `engine risk-signals <slug>` prints matching signals. |
| **`spec_write_timestamp`** | An epoch-seconds field in `state.json` bumped by every `/f-spec` write. Used by the plan staleness gate (compares against `plan.md` mtime). Exists because `/f-pause` stashes destroy filesystem mtimes. |
| **`SDD_NON_INTERACTIVE=1`** | Env var that suppresses bash prompts in `/f-start` (branch creation), `/f-commit` (message confirmation), and `/f-close` (confirmation). Set by `/f-auto` for the non-interactive autopilot. Override manually with `SDD_NON_INTERACTIVE=1` to skip prompts in any command. |
| **Vibe coding** | `/f-commit`, `/f-mr`, and `/f-code-review` work on **any branch with no pipeline setup**. No `.specwork/`, no spec, no plan needed. See [VIBE-CODING.md](vibe-coding.md). |
| **Quality gates** | `bash commands/check.sh` must pass before `/f-commit` and `/f-mr`. Failed checks block progression. open-sdd ships a stack-detecting default (`npm test`, `./gradlew check`, `mvn verify`, `pytest`, etc.). Projects override by placing their own `commands/check.sh`. |
| **Service-rules are a convention** | `.opensdd/service-rules.md` is not auto-discovered by the LLM. The project's pipeline instructions tell the model to load it when present. It is a pipeline convention, not a framework feature. |

---

**See also:**
- [open-sdd-architecture.md](open-sdd-architecture.md) — architectural overview
- [sdd-pipeline-cheatsheet.md](sdd-pipeline-cheatsheet.md) — command lookup
- [doc-adr-cheatsheet.md](doc-adr-cheatsheet.md) — service catalog + ADR commands
- [sdd-flashcards.md](sdd-flashcards.md) — deep-dive Q&A
- [VIBE-CODING.md](vibe-coding.md) — standalone commands without pipeline
