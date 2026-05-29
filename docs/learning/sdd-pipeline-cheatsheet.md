# SDD Pipeline — Command Reference

Quick lookup for every pipeline command available in this project. Each maps to a script under `commands/`.

## Entry & Spec

| Command | What it does |
|---------|--------------|
| **`/f-start <ticket-or-text>`** | Initialize pipeline: fetch Jira (or free-text), create/select branch, write `.specwork/` state + `source.md`. **Does NOT create `spec.md`** — that is `/f-spec`'s job. Always run first. |
| **`/f-spec [files \| jira X \| paste \| "text"]`** | Drafts the spec the first time (when `spec.md` has no sections) and refines it on subsequent calls. Idempotent; always bumps `spec_write_timestamp`. Warns if plan becomes stale. Replaces deprecated `/f-spec-refine` (wrapper still forwards here). |

## Plan & Implement

| Command | What it does |
|---------|--------------|
| **`/f-plan`** | Discover target files via 6 heuristics and write a plan under `.specwork/_plan/`. Optional — `/f-implement` falls back to inline discovery if no plan exists. |
| **`/f-implement`** (N times) | One focused step per invocation. Gates: blocks on unresolved Open Questions or stale plan. Runs inline tests per step. On completion, recommends phase: low complexity → `/f-commit`, high complexity → `/f-test-design`. |
| **`/f-implement --done N`** | Mark step N as complete. Use after manually addressing a step that had Open Questions. |

## Test (Optional)

| Command | What it does |
|---------|--------------|
| **`/f-test-design`** | Design test cases stack-aware (Java: `@SpringBootTest`/`@WebMvcTest`/`@DataJpaTest`; Frontend: RTL + MSW). Non-negotiable: must include at least one integration scenario per primary behavior unit. Works standalone — no SDD required. |
| **`/f-test-impl`** | Implement the designed tests. Produces `*Test.java`/`*IT.java` (Java with Playwright skeleton) or `*.test.tsx` (Frontend). Standalone. |

## Commit, Review, MR

| Command | What it does |
|---------|--------------|
| **`/f-commit`** | Generate a semantic commit message. Auto-stages working tree files if nothing is staged. One logical commit per feature step. Quality gate: runs `commands/check.sh` before committing. |
| **`/f-code-review`** | Stack-aware review of the diff (Java or UI reviewers depending on `build.gradle`/`package.json`). Emits findings with severity (BLOCKING / IMPORTANT / OPTIONAL) plus **Suggested Follow-ups** linking to relevant review packs (`/jpa-patterns`, etc.). Use `--recheck` to compare against previous report. |
| **`/f-mr`** | Pre-push validation (runs `commands/check.sh`), optionally publishes spec to `docs/specs/`, pushes branch, creates GitLab MR via glab. Use `--skip-validation` for emergencies only. |

## After MR

| Command | What it does |
|---------|--------------|
| **`/f-mr-address`** | Work through MR review comments one thread at a time with minimal guidance per thread. Progress tracked in `.specwork/_review/`. |
| **`/f-close`** | Wipe `.specwork/` after MR merge. Verifies MR status before deleting unmerged work. |

## Context Switching & Utilities

| Command | What it does |
|---------|--------------|
| **`/f-pause`** | Stash everything (working tree + `.specwork/`) without switching branches. |
| **`/f-resume`** | List paused pipeline branches and restore the selected one. |
| **`/f-resync`** | Rename `.specwork/` artifacts after a branch rename. Sync-only (0 args) or atomic (1 arg: `git branch -m` + sync). |
| **`/f-handoff`** | Package spec + rules + state into a model-agnostic execution capsule for handoff to another agent. |
| **`/f-help`** | "Where am I + what's next?" — quick navigation of the current pipeline state. |
| **`/f-status`** | Detailed status of the active pipeline branch. |

---

**See also:**
- [open-sdd-architecture.md](open-sdd-architecture.md) — architectural overview
- [sdd-key-concepts.md](sdd-key-concepts.md) — cross-cutting concepts
- [doc-adr-cheatsheet.md](doc-adr-cheatsheet.md) — service catalog + ADR commands
- [sdd-flashcards.md](sdd-flashcards.md) — deep-dive Q&A on pipeline mechanics
