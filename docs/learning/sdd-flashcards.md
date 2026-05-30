# SDD Pipeline — Flashcards

Hard questions about the spec-driven development pipeline as it applies to this project. Covers artifact layout, pipeline instruction consumption, architecture, quality gates, non-interactive mode, plan heuristics, engine internals, and git mechanics.

**See also:**
- [open-sdd-architecture.md](open-sdd-architecture.md) — architectural overview
- [sdd-pipeline-cheatsheet.md](sdd-pipeline-cheatsheet.md) — command lookup
- [sdd-key-concepts.md](sdd-key-concepts.md) — cross-cutting concepts
- [doc-adr-cheatsheet.md](doc-adr-cheatsheet.md) — service catalog + ADR commands
- [vibe-coding.md](vibe-coding.md) — standalone commands without pipeline

```
┌──────┬────────────────────────────────────────────────────────────┬─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│  #   │                          Question                          │                                                                  Answer                                                                 │
├──────┼────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│  1   │ What is open-sdd?                                          │ Spec-Driven Development pipeline. A deterministic protocol that takes a feature from ticket to Merge Request through strict gates:       │
│      │                                                            │ start → plan → implement → test → commit → MR. Every step produces versioned artifacts under `.specwork/`.                                 │
├──────┼────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│  2   │ What is the pipeline flow?                                 │ `/f-start` → [`/f-plan`] → `/f-implement` → [`/f-test-design` → `/f-test-impl`] → `/f-commit` → `/f-mr`. Plan and test steps are    │
│      │                                                            │ optional. At any point: `/f-pause`, `/f-resume`, `/f-status`, `/f-code-review`, `/f-handoff`. `/f-auto` runs the full flow              │
│      │                                                            │ non-interactively.                                                                                                                       │
├──────┼────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│  3   │ Where does pipeline state live?                            │ `.specwork/` at the project root. Subdirs: `_spec/`, `_plan/`, `_state/`, `_test/`, `_progress/`, `_review/`, `_handoff/`. |
│      │                                                            │ State is file-based, not database.                                                                                                        │
├──────┼────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│  4   │ How does the LLM consume the pipeline instructions?           │ The pipeline instructions are loaded as system instructions at session start. The model reads them whole — prose, bullets, sub-bullets,  │
│      │                                                            │ section semantics (severities, Quality Gates, OQ rules) — with zero loss.                                                               │
├──────┼────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│  5   │ How does the SDD pipeline consume the pipeline instructions?  │ In a single step at `/f-start`. `start.sh` reads the project's pipeline instructions + `.opensdd/service-rules.md` and compiles them into │
│      │                                                            │ `.specwork/_state/<slug>-rules.json`. Compilation is lossy: regex `(?m)^- (.+)$` only captures top-level bullets, capped at 20.          │
│      │                                                            | Sub-bullets and section prose are discarded.                                                                                              |
├──────┼────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│  6   │ Do downstream skills read the pipeline instructions again? │ No. They read `rules.json`. `/f-handoff` explicitly says: "Do not read the pipeline instructions or service-rules.md directly."           | 
├──────┼────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│  7   │ Is the pipeline instructions file auto-discovered by the   │ No. The LLM's skill system only scans for `SKILL.md` files. The pipeline instructions at the project root are sourced from a template.    │
│      │ LLM?                                                       │ The model reads them as system instructions.                                                                                               │
├──────┼────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│  8   │ Is .opensdd/service-rules.md auto-discovered by the LLM?   │ No. Unlike the pipeline instructions, the LLM has no built-in discovery for it. The project's pipeline instructions tell the model to     │
│      │                                                            │ load it explicitly when it exists. It is a pipeline convention, not a framework feature.                                                  │
├──────┼────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│  9   │ Why do SDD /f-* commands have scripts but doc /adr-*       │ SDD pipeline commands have dedicated `commands/*.sh` scripts. Doc/ADR commands also have standalone scripts registered by `install.sh`.     │
│      │ commands don't?                                            │ Both are project-local scripts. Separation of concerns: pipeline commands stay local; doc/ADR commands are globally available.              │
│      │                                                            │                                                                                                                                            |
├──────┼────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ 10   │ What does start.sh generate?                               │ Four artifacts in one call: (1) `rules.json` — compiled rules from the pipeline instructions + service-rules.md; (2)                     │
│      │                                                            │ `implementation-cache.json` — empty arrays; (3) `state.json` — pipeline metadata; (4) `source.md` — raw source (Jira or free text).      │
│      │                                                            │ and does NOT run triage.                                                                                                                   │
├──────┼────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ 11   │ What is lost when the pipeline instructions are compiled   │ (a) Sub-bullets — regex `(?m)^- (.+)$` only matches top-level bullets. (b) Semantic section structure — severity levels, OQ rules,       │
│      │ to rules.json?                                              │ Quality Gates are prose under headings. (c) Items beyond the 20-bullet cap.                                                              │
├──────┼────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ 12   │ What does engine triage do?                                │ `engine triage <slug>` classifies ticket complexity by analyzing the spec body. Scans for high-risk keywords (auth, migration,           │
│      │                                                            │ concurrency) and estimates change scope (files touched, known layers). Writes `.specwork/_state/<slug>-path.json` with complexity tier,   │
│      │                                                            │ recommended steps, and signals. Runs after `/f-spec` first draft (recommended by spec.sh output), NOT during `/f-start`.                  │
├──────┼────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ 13   │ What is the handoff contract?                              │ `.specwork/_handoff/<slug>-execution-pack.md`. A self-contained artifact including source, spec, plan, state, rules, cache, and OQs.     │
│      │                                                            │ Designed to be consumed without access to the pipeline instructions, service-rules.md, or skill files.                                    │
├──────┼────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ 14   │ When should an Open Question be created?                   │ Only for: ambiguous behavior, missing dependencies, conflicting rules/contracts, unsafe implementation conditions. Not for: optional       │
│      │                                                            │ refactors, stylistic preferences, speculative improvements.                                                                               │
├──────┼────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ 15   │ What happens when an OQ is BLOCKING?                       │ It stops progression. The pipeline refuses to advance until resolved. Blocking OQs gate `/f-implement`, `/f-commit`, and `/f-mr`.        │
├──────┼────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ 16   │ What must pass before committing?                          │ `bash commands/check.sh`. Applies to both `/f-commit` and `/f-mr`. Failed checks block progression.                                      │
├──────┼────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ 17   │ Where are service catalogs stored?                         │ In `$OPEN_SDD_DOC_HOME/service-catalog/` (default `${OPEN_SDD_ROOT:-~}/.opensdd/registry/service-catalog/`). Managed by `/doc-publish`     │
│      │                                                            │ and queried by `/doc-query`.                                                                                                               │
├──────┼────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ 18   │ Where are ADRs stored?                                     │ In `$OPEN_SDD_DOC_HOME/adr-registry/<service-name>/` (default `${OPEN_SDD_ROOT:-~}/.opensdd/registry/adr-registry/`). Managed by          │
│      │                                                            | `/adr-publish` and queried by `/adr-query`.                                                                                                |
├──────┼────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ 19   │ What is OPEN_SDD_DOC_HOME for?                             │ Overrides the registry root for team-shared registries (e.g., a cloned GitLab repo). Affects all four doc commands: `/doc-publish`,         │
│      │                                                            │ `/doc-query`, `/adr-publish`, `/adr-query`.                                                                                               │
├──────┼────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ 20   │ Does the model have persistent memory between sessions?    │ No. Each session starts blank. Persistent knowledge must be written to files — pipeline instructions, docs/, `.opensdd/service-rules.md`, │
├──────┼────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ 21   │ What is the role of state.json vs rules.json vs            │ `state.json` = deterministic feature metadata (slug, ticket, branch, base, paths, timestamps). `rules.json` = compiled service rules      │
│      │ implementation-cache.json?                                 │ frozen at `/f-start`. `implementation-cache.json` = append-only local memory of discovered repos, patterns, related tests — written by    │
│      │                                                            | `/f-start` and `/f-implement`.                                                                                                              |
├──────┼────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ 22   │ What is _progress/escalations.md and what triggers it?     │ Append-only runtime log of `/f-implement` escalation hits (test loops, infra failures, persistent retries). Lives in `_progress/`        │
│      │                                                            │ (mutable execution memory). Consumed by `/f-handoff` to surface known blockers so an external executor avoids repeated failures.         │
├──────┼────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ 23   │ What sections does the generated spec.md include?          │ 8 top-level sections: ## Summary, ## Scope (### In scope / Out of scope), ## Behavior, ## Implementation Context,                       │
│      │                                                            │ ## Expected Change Scope, ## Safe Constraints (### Safe / ### Unsafe), ## Open Questions.                                                  │
├──────┼────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ 24   │ What 4 input types does /f-spec accept?                    │ (1) File paths (detected by `/` or extensions), (2) `jira <TICKET>`, (3) `paste` (stdin), (4) Inline free text in quotes. YES — mixable  │
│      │                                                            │ in one call. Each keeps its provenance label. (/f-spec-refine kept as deprecated alias.)                                                  │
├──────┼────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ 25   │ What does /f-spec NEVER touch?                             │ `source.md` (frozen at `/f-start`), `rules.json` (compiled rules), git state (no commits, branch ops, or stash). Downstream artifacts —  │
│      │                                                            │ only warns about staleness, never deletes or rewrites.                                                                                    │
├──────┼────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ 26   │ When is the Plan Staleness Gate skipped?                   │ When `plan.md` does not exist (no-plan workflow). In that case `/f-implement` falls back to inline discovery. The gate fires on ANY spec  │
│      │                                                            │ `spec_write_timestamp` > plan mtime.                                                                                                       │
├──────┼────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ 27   │ Does /f-mr's ADR Hint invoke /doc-adr automatically?       │ No. It only prints a tip: "Consider running /doc-adr" if the spec has resolved OQs. The user decides. Never auto-invokes.                │
├──────┼────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ 28   │ What flag overrides /f-mr's pre-push validation?           │ `--skip-validation`. Documented for emergencies only. Normal use is forbidden — override is intentionally explicit so it shows in shell  │
│      │                                                            │ history.                                                                                                                                   |
├──────┼────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ 29   │ Sync-only vs atomic mode in /f-resync?                     │ 0 args → sync-only: assume git already renamed; only update `.specwork/` files. 1 arg → atomic: run `git branch -m` first, then sync.   │
├──────┼────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ 30   │ What MR-status outcomes cause /f-close to proceed vs warn? │ `merged` → proceed silently. `open` or `closed-unmerged` → warn before deleting. Destructive scope: ONLY `.specwork/` — never touches     │
│      │                                                            │ source tree, commits, or `docs/`.                                                                                                          │
├──────┼────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ 31   │ What does /f-auto do?                                      │ Non-interactive autopilot. Runs `/f-start → /f-spec → OQ check → /f-plan → /f-implement` with `SDD_NON_INTERACTIVE=1`. Stops for        │
│      │                                                            │ human input at two points: unresolved OQs and when a concrete risk signal fires. Results in an open MR.                                   │
├──────┼────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ 32   │ What is SDD_NON_INTERACTIVE?                               │ An env var (`SDD_NON_INTERACTIVE=1`) that suppresses bash prompts in `/f-start` (branch creation), `/f-commit` (message approval), and    │
│      │                                                            | `/f-close` (confirmation). Set by `/f-auto`. Override manually to skip prompts in any command.                                              |
├──────┼────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ 33   │ What does detect_stack() return?                           │ Three values: `"java"` (build.gradle/pom.xml), `"node"` (package.json only), `"unknown"` (neither). Every command switches heuristics    │
│      │                                                            │ based on the return value: Java gets Spring Boot patterns (ExceptionHandler, ControllerAdvice, Maven/Gradle test layout); Node gets       │
│      │                                                            │ Jest/Vitest patterns, `__tests__/` discovery, Express/NestJS infra.                                                                       │
├──────┼────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ 34   │ What are risk signals and how are they different from      │ Risk signals are deterministic regex matches (detect_risk_signals) for 5 signals: db-migration, auth-security, breaking-api,              │
│      │ triage?                                                    │ data-destructive, concurrency. They are NOT the fuzzy triage tier. `/f-auto` uses them to decide if optional test steps are needed.       │
│      │                                                            | Triage (engine triage) is a broader classification (trivial/focused/standard/high-risk) based on keywords + estimated file count.          |
├──────┼────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ 35   │ What is spec_write_timestamp?                              │ An epoch-seconds integer in state.json bumped by every `/f-spec` write. The plan staleness gate compares it against plan.md mtime.        │
│      │                                                            │ Exists because `/f-pause` uses `git stash` which destroys filesystem mtimes — the stored timestamp survives stash/unstash.                │
├──────┼────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ 36   │ What is vibe coding?                                       │ Using `/f-commit`, `/f-mr`, and `/f-code-review` on any branch without creating `.specwork/` artifacts. No spec, no plan, no pipeline.     │
│      │                                                            │ See docs/learning/vibe-coding.md.                                                                                                                   │
├──────┼────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ 37   │ How does /f-mr detect which provider to use?               │ Auto-detects from the remote: `git remote get-url origin`. If it contains `github.com` → `gh`. Otherwise → `glab`. Override with         │
│      │                                                            │ `OPEN_SDD_MR_PROVIDER=github|gitlab` (needed for self-hosted GitLab).                                                                     │
├──────┼────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ 38   │ What are the two layers of the pipeline?                   │ 1) Bash layer (`commands/*.sh`): thin orchestrators handling I/O, git, printing, prompts. 2) Python engine (`engine/`): pure decision      │
│      │                                                            │ layer with no git side effects. The bash layer calls `python3 -m engine.cli <cmd>` for every decision.                                   │
├──────┼────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ 39   │ How does install.sh work?                                  │ Copies 19 `commands/*.sh` scripts to the pipeline commands directory. Also registers doc/ADR commands.   │
│      │                                                            │ Prints a post-install requirements check. Is the single source of truth for the command catalog.                                          │
├──────┼────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ 40   │ What is the architecture file structure?                   │ `agent/` (LLM instructions) + `lib/` (gates.sh, jira.sh) + `commands/` (19 scripts) + `engine/` (Python decision layer) +                  │
│      │                                                            │ `templates/` (scaffolds for consumer projects) + `tests/` (104 unit tests) + `docs/` (learning docs, presentation).                        │
├──────┼────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ 41   │ How does /f-spec detect draft vs refine mode?              │ By checking if `spec.md` exists. If absent → draft mode (creates spec from source.md + template). If present → refine mode (integrates    │
│      │                                                            │ new context into existing spec, append-only on OQs). Called with no args in refine mode is a strict no-op.                                │
├──────┼────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ 42   │ How does resolve_slug() work?                               │ First reads the current git branch, then scans `.specwork/_state/*-state.json` for a `branch` field match. If found, returns that file's  │
│      │                                                            │ slug. Falls back to slugifying the branch name. Commands fail with `COULD_NOT_RESOLVE_SLUG` outside a branch with state.                  │
├──────┼────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ 43   │ What are the 6 plan discovery heuristics in /f-plan?       │ 1) **infra** — cross-cutting files (exception handlers, error boundaries). 2) **mock-consumer** — test files mocking discovered classes.   │
│      │                                                            │ 3) **test-naming guard** — resolve test paths from source files. 4) **reference-update grep** — symbols marked for rename/removal.        │
│      │                                                            │ 5) **spec consistency** — detect contradictory requirements. 6) **risk surface** — hard keyword matches for risk signals.                 │
├──────┼────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ 44   │ What is the reference-update grep guard system?             │ Three guards: 1) Skip Safe Constraints section (preservation language, not rename targets). 2) Skip negated lines ("Do NOT remove ...").  │
│      │                                                            │ 3) Per-symbol hit cap (OPEN_SDD_REF_HIT_CAP, default 8) — tokens matching more files are generic and silently skipped.                    │
├──────┼────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ 45   │ What spec consistency pairs does check_spec_consistency      │ Four pairs: (a) idempotent + per-call side effect (needs resolver: transaction/saga/orchestrator). (b) remove + still-referenced.          │
│      │ detect?                                                     │ (c) atomic + multi-step (needs resolver: coordinator/orchestrator). (d) cache + always fresh (needs resolver: invalidate/expire/ttl).     │
├──────┼────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ 46   │ How does /f-commit behave without a pipeline (vibe mode)?   │ Auto-stages tracked changes if nothing staged. Runs `commands/check.sh` as quality gate (non-zero stops commit). Builds message from      │
│      │                                                            │ branch name (`feature/JIRA-123-foo` → `[JIRA-123] feat: ...`). Pipeline-only extras (writing checked_sha into state.json) are skipped.    │
├──────┼────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ 47   │ How does /f-code-review detect pack hints?                  │ For Java: greps diff for `@Entity`/`@Repository` → JPA patterns; `@Async`/CompletableFuture → concurrency; `@RestController` → API        │
│      │                                                            │ contracts; `@Slf4j`/MDC → logging patterns. Each match prints a "consider" hint linking to a review pack.                                 │
├──────┼────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ 48   │ What machine-readable tokens does the engine print?         │ `SPECWORK_OK`, `GATES_PASSED`, `UNRESOLVED_OQS`, `PLAN_STALE`, `ALREADY_INITIALIZED`, `NO_SPECWORK`, `NO_STATE`, `BRANCH_MISMATCH`,          │
│      │                                                            │ `COULD_NOT_RESOLVE_SLUG`. The bash layer greps on these to decide next action. JSON payloads for plan data and check results.              │
├──────┼────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ 49   │ How does /f-pause work?                                     │ Verifies pipeline state exists. `git add -A` (tracked + untracked, excluding gitignored). `git add -f .specwork/` (force-add gitignored    │
│      │                                                            │ artifacts). `git stash push --message "f-pause: <branch>"`. Only stages what was explicitly added — NOT all ignored files.                 │
├──────┼────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ 50   │ How does /f-resume work?                                    │ Runs `git stash list --format="%gd %s" | grep "f-pause:"` to find pipeline stashes. Shows menu by branch name. Verifies clean tree.       │
│      │                                                            │ `git switch <branch>` (or `-c` if gone). `git stash pop <ref>`. Deduplicates: after pop, drops older stashes with same branch name.       │
├──────┼────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ 51   │ What is the OQ format and how are they resolved?            │ Format: `- [ ] **#N** <question>` in spec.md or plan.md. /f-spec refine mode flips resolved OQs to `- [x] **#N** <question> — resolved:    │
│      │                                                            │ <answer>`. The check_open_questions gate scans both files for any `- [ ]` under `## Open Questions`.                                      │
├──────┼────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ 52   │ What happens when check.sh fails?                           │ The commit or push is blocked. `/f-commit` refuses to create the commit. `/f-mr` refuses to push. The user must fix the failure and       │
│      │                                                            │ re-run. Use `--skip-validation` on `/f-mr` for emergencies only (documented for incident response).                                      │
├──────┼────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ 53   │ How does /f-implement handle no-plan vs plan mode?          │ No-plan: discovers targets inline from the spec's Implementation Context. Plan mode: reads `plan.json` for target files, supports         │
│      │                                                            │ `/f-implement --done N` to mark steps complete. Writes to `implementation-cache.json` in both modes.                                      │
├──────┼────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ 54   │ What fields does implementation-cache.json store?           │ `schema_version`, `id` (slug), `repositories`, `patterns`, `related_tests`, `similar_classes`, `notes`. Append-only: discovered facts     │
│      │                                                            │ are added, never removed. Written by `/f-start`, `/f-plan`, and `/f-implement`.                                                           │
├──────┼────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ 55   │ How does state.json handle unknown legacy keys?             │ Through the `extra` dict field. `from_dict`/`to_dict` round-trip any on-disk keys not in the dataclass (legacy `id`, `input_type`, etc.)  │
│      │                                                            │ by storing them in `extra`. Removing a field would drop legacy data on save — `extra` preserves it deliberately.                          │
├──────┼────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ 56   │ How does /f-handoff work?                                   │ Packages spec + rules + state + cache into `.specwork/_handoff/<slug>-execution-pack.md`. Gates: requires state, rules, spec, and no      │
│      │                                                            │ unresolved OQs. No-enrichment rule: only packages existing artifacts, never generates new content. Also writes execution-pack.json.        │
├──────┼────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ 57   │ What 6 doc/ADR companion commands does open-sdd bundle?       │ `/doc-catalog` (scan service → docs/service-info.md), `/doc-publish` (publish to registry), `/doc-query` (cross-service questions),        │
│      │                                                            │ `/doc-adr` (create ADR in docs/adr/), `/adr-publish` (publish ADRs to registry), `/adr-query` (decision-history questions).               │
├──────┼────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ 58   │ How does /f-test-impl list (dry-run) mode work?             │ `./commands/test-impl.sh list` runs a read-only preview. Reads the git diff, resolves each changed source file to expected test paths,   │
│      │                                                            │ and prints which tests exist (UPDATE) and which don't (CREATE). No files are written. The real run (without `list`) implements them.       │
├──────┼────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ 59   │ How does /f-mr handle pre-push test validation?             │ Runs `commands/check.sh` before pushing. Skips validation if HEAD's `checked_sha` matches the current HEAD (meaning /f-commit already      │
│      │                                                            │ validated this exact commit). Stops entirely if tests fail. `--skip-validation` bypasses the gate.                                         │
└──────┴────────────────────────────────────────────────────────────┴─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
```
