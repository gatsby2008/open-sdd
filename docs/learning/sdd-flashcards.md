# SDD Pipeline — Flashcards

Hard questions about the spec-driven development pipeline as it applies to this project. Covers artifact layout, AGENTS.md consumption, architecture, quality gates, and non-interactive mode.

**See also:**
- [open-sdd-architecture.md](open-sdd-architecture.md) — architectural overview
- [sdd-pipeline-cheatsheet.md](sdd-pipeline-cheatsheet.md) — command lookup
- [sdd-key-concepts.md](sdd-key-concepts.md) — cross-cutting concepts
- [doc-adr-cheatsheet.md](doc-adr-cheatsheet.md) — service catalog + ADR commands
- [VIBE-CODING.md](vibe-coding.md) — standalone commands without pipeline

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
│  3   │ Where does pipeline state live?                            │ `.specwork/` at the project root. Subdirs: `_spec/`, `_plan/`, `_state/`, `_test/`, `_progress/`, `_review/`, `_handoff/`, `_metrics/`. |
│      │                                                            │ State is file-based, not database.                                                                                                        │
├──────┼────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│  4   │ How does opencode consume AGENTS.md?                       │ opencode auto-discovers `AGENTS.md` at the project root and injects it as system instructions at session start. The model reads it       │
│      │                                                            │ whole — prose, bullets, sub-bullets, section semantics (severities, Quality Gates, OQ rules) — with zero loss.                           │
├──────┼────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│  5   │ How does the SDD pipeline consume AGENTS.md?               │ In a single step at `/f-start`. `start.sh` reads the project's `AGENTS.md` + `.opensdd/service-rules.md` and compiles them into          │
│      │                                                            │ `.specwork/_state/<slug>-rules.json`. Compilation is lossy: regex `(?m)^- (.+)$` only captures top-level bullets, capped at 20.          │
│      │                                                            | Sub-bullets and section prose are discarded.                                                                                              |
├──────┼────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│  6   │ Do downstream skills read AGENTS.md again?                 │ No. They read `rules.json`. `/f-handoff` explicitly says: "Do not read AGENTS.md or service-rules.md directly."                          | 
├──────┼────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│  7   │ Is the AGENTS.md at the project root used by Claude        │ No. Claude Code's skill system only scans for `SKILL.md` files. The `AGENTS.md` at the project root is generated by `install.sh` from    │
│      │ Code?                                                      │ the template. The model reads it as system instructions via opencode's AGENTS.md.                                                         │
├──────┼────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│  8   │ Is .opensdd/service-rules.md auto-discovered by opencode?  │ No. Unlike `AGENTS.md`, opencode has no built-in discovery for it. The project's `AGENTS.md` instructs the model to load it explicitly    │
│      │                                                            │ when it exists. It is a pipeline convention, not an opencode framework feature.                                                           │
├──────┼────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│  9   │ Why do SDD skills have /f-* slash commands but doc skills  │ SDD skills have dedicated `commands/*.sh` scripts in this project, so they map to slash commands in `AGENTS.md`. Doc skills have no      │
│      │ don't?                                                     │ project-local scripts — they are pure skill instructions loaded on demand. Separation of concerns: pipeline stays local; skills stay      │
│      │                                                            │ portable.                                                                                                                                  |
├──────┼────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ 10   │ What does start.sh generate?                               │ Four artifacts in one call: (1) `rules.json` — compiled rules from AGENTS.md + service-rules.md; (2) `implementation-cache.json` —       │
│      │                                                            │ empty arrays; (3) `state.json` — pipeline metadata; (4) `source.md` — raw source (Jira or free text). Does NOT create spec.md              │
│      │                                                            │ and does NOT run triage.                                                                                                                   │
├──────┼────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ 11   │ What is lost when AGENTS.md is compiled to rules.json?     │ (a) Sub-bullets — regex `(?m)^- (.+)$` only matches top-level bullets. (b) Semantic section structure — severity levels, OQ rules,       │
│      │                                                            │ Quality Gates are prose under headings. (c) Items beyond the 20-bullet cap.                                                              │
├──────┼────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ 12   │ What does engine triage do?                                │ `engine triage <slug>` classifies ticket complexity by analyzing the spec body. Scans for high-risk keywords (auth, migration,           │
│      │                                                            │ concurrency) and estimates change scope (files touched, known layers). Writes `.specwork/_state/<slug>-path.json` with complexity tier,   │
│      │                                                            │ recommended steps, and signals. Runs after `/f-spec` first draft (recommended by spec.sh output), NOT during `/f-start`.                  │
├──────┼────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ 13   │ What is the handoff contract?                              │ `.specwork/_handoff/<slug>-execution-pack.md`. A self-contained artifact including source, spec, plan, state, rules, cache, and OQs.     │
│      │                                                            │ Designed to be consumed without access to AGENTS.md, service-rules.md, or skill files.                                                    │
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
│ 19   │ What is OPEN_SDD_DOC_HOME for?                             │ Overrides the registry root for team-shared registries (e.g., a cloned GitLab repo). Affects all four doc skills: `/doc-publish`,         │
│      │                                                            │ `/doc-query`, `/adr-publish`, `/adr-query`.                                                                                               │
├──────┼────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ 20   │ Does the model have persistent memory between sessions?    │ No. Each session starts blank. Persistent knowledge must be written to files — `AGENTS.md`, docs/, `.opensdd/service-rules.md`, etc.      │
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
│ 39   │ How does install.sh work?                                  │ Copies 19 `commands/*.sh` scripts to `~/.config/opencode/commands/` as opencode custom commands. Also links `skills/` for doc/ADR tools.   │
│      │                                                            │ Prints a post-install requirements check. Is the single source of truth for the command catalog.                                          │
├──────┼────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ 40   │ What is the architecture file structure?                   │ `agent/` (LLM instructions) + `lib/` (gates.sh, metrics.sh, jira.sh) + `commands/` (19 scripts) + `engine/` (Python decision layer) +     │
│      │                                                            │ `templates/` (scaffolds for consumer projects) + `tests/` (104 unit tests) + `docs/` (learning docs, presentation).                        │
└──────┴────────────────────────────────────────────────────────────┴─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
```
