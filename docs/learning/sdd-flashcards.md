# SDD Pipeline — Flashcards

Hard questions about the spec-driven development pipeline as it applies to this project. Covers artifact layout, AGENTS.md consumption, skill architecture, quality gates, and registries.

**See also:**
- [sdd-pipeline-cheatsheet.md](sdd-pipeline-cheatsheet.md) — command lookup
- [sdd-key-concepts.md](sdd-key-concepts.md) — cross-cutting concepts
- [doc-adr-cheatsheet.md](doc-adr-cheatsheet.md) — service catalog + ADR commands

```
┌─────┬──────────────────────────────────────────────────────────────┬─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ #   │                           Question                           │                                                                  Answer                                                                 │
├─────┼──────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ 1   │ What is open-sdd?                                           │ Spec-Driven Development pipeline. A deterministic protocol that takes a feature from ticket to Merge Request through strict gates:       │
│     │                                                              │ start → plan → implement → test → commit → MR. Every step produces versioned artifacts under `.specwork/`.                                 │
├─────┼──────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ 2   │ What is the pipeline flow?                                   │ `/f-start` → [`/f-plan`] → `/f-implement` → [`/f-test-design` → `/f-test-impl`] → `/f-commit` → `/f-mr`. Plan and test steps are    │
│     │                                                              │ optional. At any point: `/f-pause`, `/f-resume`, `/f-status`, `/f-code-review`, `/f-handoff`.                                            │
├─────┼──────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ 3   │ Where does pipeline state live?                              │ `.specwork/` at the project root. Subdirs: `_spec/`, `_plan/`, `_state/`, `_progress/`, `_review/`, `_handoff/`. State is file-based,   │
│     │                                                              │ not database.                                                                                                                             │
├─────┼──────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ 4   │ How does opencode consume AGENTS.md?                         │ opencode auto-discovers `AGENTS.md` at the project root and injects it as system instructions at session start. The model reads it       │
│     │                                                              │ whole — prose, bullets, sub-bullets, section semantics (severities, Quality Gates, OQ rules) — with zero loss.                           │
├─────┼──────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ 5   │ How does the SDD pipeline consume AGENTS.md?                 │ In a single step at `/f-start` (steps 7-8). `f-start.py --rules` reads `~/.claude/skills/sdd/AGENTS.md` and `./.claude/service-rules.md` │
│     │                                                              │ and compiles them into `.specwork/_state/<slug>-rules.json`. Compilation is lossy: regex `(?m)^- (.+)$` only captures top-level bullets,  │
│     │                                                              │ capped at 20. Sub-bullets and section prose are discarded.                                                                               │
├─────┼──────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ 6   │ Do downstream skills read AGENTS.md again?                   │ No. They read `rules.json`. `/f-handoff` explicitly says: "Do not read AGENTS.md or service-rules.md directly."                          │
├─────┼──────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ 7   │ Is the AGENTS.md inside ~/.claude/skills/sdd/ used by        │ No. Claude Code's skill system only scans for `SKILL.md` files. The `AGENTS.md` in that directory is a source-of-truth copy referenced  │
│     │ Claude Code?                                                 │ by the pipeline's `f-start.py --rules` flag. It is not auto-loaded by either opencode or Claude Code as instructions.                    │
├─────┼──────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ 8   │ Is .opensdd/service-rules.md auto-discovered by opencode?    │ No. Unlike `AGENTS.md`, opencode has no built-in discovery for it. The project's `AGENTS.md` instructs the model to load it explicitly  │
│     │                                                              │ when it exists. It is a pipeline convention, not an opencode framework feature.                                                          │
├─────┼──────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ 9   │ Why do SDD skills have /f-* slash commands but doc skills    │ SDD skills have dedicated `commands/*.sh` scripts in this project, so they map to slash commands in `AGENTS.md`. Doc skills have no      │
│     │ don't?                                                       │ project-local scripts — they are pure skill instructions loaded on demand. Separation of concerns: pipeline stays local; skills stay     │
│     │                                                              │ portable.                                                                                                                                 |
├─────┼──────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ 10  │ What does f-start.py generate?                               │ Four artifacts in one call: (1) `rules.json` — compiled rules; (2) `implementation-cache.json` — discovered classes; (3) `state.json` — │
│     │                                                              │ pipeline metadata; (4) `source.md` — raw source (Jira or free text).                                                                    │
├─────┼──────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ 11  │ What is lost when AGENTS.md is compiled to rules.json?       │ (a) Sub-bullets — regex `(?m)^- (.+)$` only matches top-level bullets. (b) Semantic section structure — severity levels, OQ rules,       │
│     │                                                              │ Quality Gates are prose under headings. (c) Items beyond the 20-bullet cap.                                                              │
├─────┼──────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ 12  │ What does triage.py do?                                      │ Classifies ticket complexity by analyzing the spec. Writes `.specwork/_state/<slug>-path.json` with T-shirt size, estimated steps, and   │
│     │                                                              │ risk flags. Runs at `/f-start` step 11.                                                                                                  │
├─────┼──────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ 13  │ What is the handoff contract?                                │ `.specwork/_handoff/<slug>-execution-pack.md`. A self-contained artifact including source, spec, plan, state, rules, cache, and OQs.     │
│     │                                                              │ Designed to be consumed without access to AGENTS.md, service-rules.md, or skill files.                                                   │
├─────┼──────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ 14  │ When should an Open Question be created?                     │ Only for: ambiguous behavior, missing dependencies, conflicting rules/contracts, unsafe implementation conditions. Not for: optional      │
│     │                                                              │ refactors, stylistic preferences, speculative improvements.                                                                              │
├─────┼──────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ 15  │ What happens when an OQ is BLOCKING?                         │ It stops progression. The pipeline refuses to advance until resolved. Blocking OQs gate `/f-implement`, `/f-commit`, and `/f-mr`.        │
├─────┼──────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ 16  │ What must pass before committing?                            │ `bash commands/check.sh`. Applies to both `/f-commit` and `/f-mr`. Failed checks block progression.                                     │
├─────┼──────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ 17  │ Where are service catalogs stored?                           │ In `$CLAUDE_DOC_HOME/service-catalog/` (default `~/.claude/service-catalog/`). Managed by `/doc-publish` and queried by `/doc-query`.     │
├─────┼──────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ 18  │ Where are ADRs stored?                                       │ In `$CLAUDE_DOC_HOME/adr-registry/<service-name>/` (default `~/.claude/adr-registry/`). Managed by `/adr-publish` and queried by          │
│     │                                                              │ `/adr-query`.                                                                                                                             |
├─────┼──────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ 19  │ What is CLAUDE_DOC_HOME for?                                 │ Overrides the registry root for team-shared registries (e.g., a cloned GitLab repo). Affects all four doc skills: `/doc-publish`,         │
│     │                                                              │ `/doc-query`, `/adr-publish`, `/adr-query`.                                                                                               |
├─────┼──────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ 20  │ Does the model have persistent memory between sessions?      │ No. Each session starts blank. Persistent knowledge must be written to files — `AGENTS.md`, `docs/`, etc.                               │
├─────┼──────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ 21  │ What is the role of state.json vs rules.json vs              │ `state.json` = deterministic feature metadata (slug, ticket, branch, base, paths). `rules.json` = compiled service rules frozen at       │
│     │ implementation-cache.json?                                   │ `/f-start`. `implementation-cache.json` = append-only local memory of discovered repos, patterns, related tests — written by `/f-start` │
│     │                                                              │ and `/f-implement`.                                                                                                                       │
├─────┼──────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ 22  │ What is _progress/escalations.md and what triggers it?       │ Append-only runtime log of `/f-implement` escalation hits (test loops, infra failures, persistent retries). Lives in `_progress/`        │
│     │                                                              │ (mutable execution memory). Consumed by `/f-handoff` to surface known blockers so an external executor avoids repeated failures.         │
├─────┼──────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ 23  │ What 7 sections does the generated spec.md include?          │ Summary, Scope, Behavior, Implementation Context, Expected Change Scope, Safe Constraints, Open Questions. Two extracted verbatim by    │
│     │                                                              │ `/f-handoff`: Expected Change Scope and Safe Constraints.                                                                                 │
├─────┼──────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ 24  │ What 4 input types does /f-spec-refine accept?               │ (1) File paths (detected by `/` or extensions), (2) `jira <TICKET>`, (3) `paste` (stdin), (4) Inline free text in quotes. YES — mixable  │
│     │                                                              │ in one call. Each keeps its provenance label.                                                                                             │
├─────┼──────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ 25  │ What does /f-spec-refine NEVER touch?                        │ `source.md` (frozen at `/f-start`), `rules.json` (compiled rules), git state (no commits, branch ops, or stash). Downstream artifacts —  │
│     │                                                              │ only warns about staleness, never deletes or rewrites.                                                                                    │
├─────┼──────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ 26  │ When is the Plan Staleness Gate skipped?                     │ When `plan.md` does not exist (no-plan workflow). In that case `/f-implement` falls back to inline discovery. The gate fires on ANY spec  │
│     │                                                              │ mtime > plan mtime.                                                                                                                        │
├─────┼──────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ 27  │ Does /f-mr's ADR Hint invoke /doc-adr automatically?         │ No. It only prints a tip: "Consider running /doc-adr" if the spec has resolved OQs. The user decides. Never auto-invokes.                │
├─────┼──────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ 28  │ What flag overrides /f-mr's pre-push validation?             │ `--skip-validation`. Documented for emergencies only. Normal use is forbidden — override is intentionally explicit so it shows in shell  │
│     │                                                              │ history.                                                                                                                                  |
├─────┼──────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ 29  │ Sync-only vs atomic mode in /f-resync?                       │ 0 args → sync-only: assume git already renamed; only update `.specwork/` files. 1 arg → atomic: run `git branch -m` first, then sync.   │
├─────┼──────────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ 30  │ What MR-status outcomes cause /f-close to proceed vs warn?   │ `merged` → proceed silently. `open` or `closed-unmerged` → warn before deleting. Destructive scope: ONLY `.specwork/` — never touches     │
│     │                                                              │ source tree, commits, or `docs/`.                                                                                                         │
└─────┴──────────────────────────────────────────────────────────────┴─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
```
