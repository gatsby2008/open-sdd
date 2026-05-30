# SDD Pipeline — Command Reference

Quick lookup for every pipeline command available in this project. Each maps to a script under `commands/`.

> **Vibe coding?** Three commands work without any pipeline setup:
> `/f-commit`, `/f-mr`, `/f-code-review`.
> See [VIBE-CODING.md](vibe-coding.md).

## Entry & Spec

| Command | What it does |
|---------|--------------|
| **`/f-start <ticket-or-text>`** | Initialize pipeline: fetch Jira (or free-text), create/select branch, write `.specwork/` state + `source.md`. **Does NOT create `spec.md`** — that is `/f-spec`'s job. Always run first. |
| **`/f-spec [files \| jira X \| paste \| "text"]`** | Drafts the spec the first time (when `spec.md` is absent) and refines it on subsequent calls. Idempotent; always bumps `spec_write_timestamp`. Warns if plan goes stale. Replaces deprecated `/f-spec-refine` (wrapper still forwards here). |
| **`/f-auto <ticket-or-text>`** | Non-interactive autopilot: runs `/f-start → /f-spec → /f-plan → /f-implement` without bash prompts. Sets `SDD_NON_INTERACTIVE=1`. Stops only for unresolved OQs or risk signal prompts. Ends at open MR. |

## Plan & Implement

| Command | What it does |
|---------|--------------|
| **`/f-plan`** | Discover target files via 6 heuristics (infra, mock-consumer, test-naming guard, reference-update grep, spec consistency, risk surface) and write a plan under `.specwork/_plan/`. Optional — `/f-implement` falls back to inline discovery if no plan exists. |
| **`/f-implement`** (N times) | One focused step per invocation. Gates: blocks on unresolved Open Questions or stale plan. Runs inline tests per step. On completion, recommends phase: low complexity → `/f-commit`, high complexity → `/f-test-design`. |
| **`/f-implement --done N`** | Mark step N as complete. Use after manually addressing a step that had Open Questions. |

## Test (Optional — High-Risk Flow)

| Command | What it does |
|---------|--------------|
| **`/f-test-design`** | Design test cases stack-aware (Java: `@SpringBootTest`/`@WebMvcTest`/`@DataJpaTest`; Frontend/Node: RTL + MSW). **Requires an active pipeline** — runs inside after `/f-implement`. Writes `.specwork/_test/<slug>-test-design.md`. |
| **`/f-test-impl`** | Implement the designed tests. Produces `*Test.java`/`*IT.java` (Java) or `*.test.tsx` (Frontend/Node). **Depends on test-design artifact.** Supports dry-run: `list` mode shows what files would be created/updated without writing. |

## Commit, Review, MR

| Command | What it does |
|---------|--------------|
| **`/f-commit`** | Generate a semantic commit message. Auto-stages working tree files if nothing is staged. One logical commit per feature step. Quality gate: runs `commands/check.sh` before committing. Works without pipeline (vibe coding). |
| **`/f-code-review`** | Stack-aware review of the diff (Java or Frontend/Node based on stack detection). Emits findings with severity (BLOCKING / IMPORTANT / OPTIONAL) plus **Suggested Follow-ups** linking to relevant review packs (JPA, concurrency, API, logging for Java; lifecycle, state, a11y for Frontend). Use `--recheck` to compare against previous report. Works without pipeline. |
| **`/f-mr`** | Pre-push validation (runs `commands/check.sh`), pushes branch, creates MR via GitHub CLI (`gh`) or GitLab CLI (`glab`) — auto-detects which remote is configured. Override with `OPEN_SDD_MR_PROVIDER=github|gitlab`. Works without pipeline. |

## After MR

| Command | What it does |
|---------|--------------|
| **`/f-mr-address`** | Work through MR review comments one thread at a time with minimal guidance per thread. Progress tracked in `.specwork/_review/`. |
| **`/f-close`** | Wipe `.specwork/` after MR merge. Verifies MR status (via `gh`) before deleting unmerged work. Never touches source tree, commits, or docs/. |

## Context Switching & Utilities

| Command | What it does |
|---------|--------------|
| **`/f-pause`** | Stash everything (working tree + `.specwork/`) without switching branches. |
| **`/f-resume`** | List paused pipeline branches and restore the selected one. Deduplicates stashes. |
| **`/f-resync`** | Rename `.specwork/` artifacts after a branch rename. Sync-only (0 args: assume git rename done) or atomic (1 arg: `git branch -m` + sync). |
| **`/f-handoff`** | Package spec + rules + state into a model-agnostic execution capsule for handoff to another agent. |
| **`/f-help`** | "Where am I + what's next?" — quick navigation of the current pipeline state. |
| **`/f-status`** | Detailed status of the active pipeline branch (artifact presence, OQ count, git state, next step). |

---

**19 commands total** (+ 6 doc/ADR commands: `/doc-catalog`, `/doc-publish`, `/doc-query`, `/doc-adr`, `/adr-publish`, `/adr-query`).

**See also:**
- [open-sdd-architecture.md](open-sdd-architecture.md) — architectural overview
- [sdd-key-concepts.md](sdd-key-concepts.md) — cross-cutting concepts
- [doc-adr-cheatsheet.md](doc-adr-cheatsheet.md) — service catalog + ADR commands
- [sdd-flashcards.md](sdd-flashcards.md) — deep-dive Q&A on pipeline mechanics
- [VIBE-CODING.md](vibe-coding.md) — standalone commands without pipeline
