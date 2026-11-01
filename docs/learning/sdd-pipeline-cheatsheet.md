# SDD Pipeline — Command Reference

Quick lookup for every pipeline command available in this project. Each maps to a script under `commands/`.

> **Vibe coding?** These commands work without any pipeline setup:
> `/f-commit`, `/f-mr`, `/f-code-review`, `/f-mr-review`, `/f-undo`.
> See [VIBE-CODING.md](vibe-coding.md).

## Entry & Spec

| Command | What it does |
|---------|--------------|
| **`/f-start <ticket-or-text>`** | Initialize pipeline: fetch Jira (or free-text), create/select branch, write `.specwork/` state + `source.md`. **Does NOT create `spec.md`** — that is `/f-spec`'s job. Always run first. |
| **`/f-spec [files \| jira X \| paste \| "text"]`** | Drafts the spec the first time (when `spec.md` is absent) and refines it on subsequent calls. Gives each Behavior a stable id (`B1`, `B2`…). The first draft runs triage. Refine without arguments is a no-op; otherwise it bumps `spec_write_timestamp`. Warns if plan goes stale. |
| **`/f-spec --tier <tier> "<reason>"`** | Force the triage tier (`trivial` / `focused` / `standard` / `high-risk`) when keywords misjudged it; sticky, `--tier auto` drops it. Does not touch the spec. |
| **`/f-auto <ticket-or-text>`** | Non-interactive autopilot: runs `/f-start → /f-spec → /f-plan → /f-implement → /f-commit → /f-mr` without bash prompts (`SDD_NON_INTERACTIVE=1`) and stops at the open MR. It pauses only for unresolved OQs (after `/f-spec`, hard stop) and — when the spec hit a risk area — to ask about the optional `/f-test-design`/`/f-test-impl` steps (after `/f-implement`). No risk signals → straight through `/f-commit` and `/f-mr`. Never runs `/f-close` or `/f-mr-address`. |

## Plan & Implement

| Command | What it does |
|---------|--------------|
| **`/f-plan`** | Discover target files via 6 heuristics (infra, mock-consumer, test-naming guard, reference-update grep, spec consistency, risk surface) and write a plan under `.specwork/_plan/`. Optional, except for **high-risk** pipelines — elsewhere `/f-implement` falls back to inline discovery if no plan exists. |
| **`/f-implement`** (N times) | One focused step per invocation. Gates: blocks on unresolved Open Questions, on a high-risk pipeline without a plan, or on a stale plan. Writes tests tagged `spec: B<n>` and runs them per step. On completion, recommends phase: low complexity → `/f-commit`, high complexity → `/f-test-design`. |
| **`/f-implement --done N`** | Mark step N as complete. Use after manually addressing a step that had Open Questions. |

## Test (Optional — High-Risk Flow)

| Command | What it does |
|---------|--------------|
| **`/f-test-design`** | Design test cases stack-aware (Java: `@SpringBootTest`/`@WebMvcTest`/`@DataJpaTest`; Frontend/Node: RTL + MSW). **Requires an active pipeline** — runs inside after `/f-implement`. Writes `.specwork/_test/<slug>-test-design.md`. |
| **`/f-test-impl`** | Implement the designed tests. Produces `*Test.java`/`*IT.java` (Java) or `*.test.tsx` (Frontend/Node). **Depends on test-design artifact.** Supports dry-run: `list` mode shows what files would be created/updated without writing. |

## Commit, Review, MR

| Command | What it does |
|---------|--------------|
| **`/f-commit`** | Generate a semantic commit message. Auto-stages working tree files if nothing is staged. One logical commit per feature step. Runs the test-coverage gate; `commands/check.sh` runs later, before the push (`/f-mr`). Advisory: lists Behaviors without a tagged test and, on high-risk pipelines, asks once per diff for `/f-code-review --auditor`. Works without pipeline (vibe coding). |
| **`/f-code-review`** | Stack-aware review of the diff (Java or Frontend/Node based on stack detection). Emits findings with severity (BLOCKING / IMPORTANT / OPTIONAL) plus **Suggested Follow-ups** linking to relevant review packs (JPA, concurrency, API, logging for Java; lifecycle, state, a11y for Frontend). Use `--recheck` to compare against previous report; `--auditor` is the report-only mode `/f-commit` asks for on high-risk pipelines. Works without pipeline. |
| **`/f-mr-review <branch \| mr-url \| mr-iid>`** | Stack-aware review of **someone else's** committed changes — a peer's branch or MR. Resolves the diff via `glab mr diff` (MR mode) or `git diff` (branch mode). Same review engine as `/f-code-review`. Never checks out the branch or modifies your working tree. |
| **`/f-mr`** | Pre-push validation (runs `commands/check.sh`), pushes branch, creates MR via GitHub CLI (`gh`) or GitLab CLI (`glab`) — auto-detects which remote is configured. Override with `OPEN_SDD_MR_PROVIDER=github|gitlab`. Works without pipeline. |

## After MR

| Command | What it does |
|---------|--------------|
| **`/f-mr-address`** | Work through MR review comments one thread at a time with minimal guidance per thread. Progress tracked in `.specwork/_review/`. |
| **`/f-close`** | Run after the MR merges. First offers to promote durable rules from the spec into `.claude/rules/*.md` (you approve each); then **reverts uncommitted changes**, wipes `.specwork/` and `.opensdd/`, and offers branch cleanup. Refuses when `.specwork/` belongs to another branch. |

## Recovery: undo/redo with opencode

When the agent implements something incorrectly, **you do not need to restart the pipeline**. opencode provides native commands that revert code changes without touching `.specwork/`:

| Action | Command | What it does |
|--------|---------|--------------|
| Revert last step | `/undo` | Reverts changes from the agent’s last message (code + conversation). Does not touch `.specwork/`. |
| Restore reverted step | `/redo` | Restores the message and changes that `/undo` reverted. |
| Compact context | `/compact` | When the session gets long, compresses history to free context. Pipeline state (`.specwork/`) stays intact. |

**Typical recovery flow:**

```
/f-implement → bad implementation output → /undo
  └── code reverted, .specwork/ intact
       ├── spec issue → /f-spec <context> → refine spec
       ├── plan issue → /f-plan → refresh plan
       └── execution-only issue → /f-implement again
```

Without these commands, the fallback is often `/f-close`, which wipes `.specwork/` and forces a full restart with `/f-start`.

## Context Switching & Utilities

| Command | What it does |
|---------|--------------|
| **`/f-pause`** | Stash everything (working tree + `.specwork/`) without switching branches. |
| **`/f-resume`** | List paused pipeline branches and restore the selected one. Deduplicates stashes. |
| **`/f-resync`** | Resync `.specwork/` artifacts with the current branch. Default: sync-only (`/f-resync`). Atomic mode: `/f-resync --rename-branch <new-branch>` (runs `git branch -m` + sync). |
| **`/f-undo`** | Discard uncommitted changes reversibly (stash); `--restore` recovers, `--hard --force` discards for good. Keeps `.specwork/`. |
| **`/f-handoff`** | Package spec + rules + state into a model-agnostic execution capsule for handoff to another agent. |
| **`/f-help`** | "Where am I + what's next?" — quick navigation of the current pipeline state. |
| **`/f-status`** | Detailed status of the active pipeline branch (artifact presence, OQ count, git state, next step). |

---

**29 commands total** (20 pipeline + 9 doc/ADR/spec/investigation/architecture commands).

**See also:**
- [open-sdd-architecture.md](open-sdd-architecture.md) — architectural overview
- [specwork-artifacts.md](specwork-artifacts.md) — `.specwork/` folders/files, producers, consumers
- [sdd-key-concepts.md](sdd-key-concepts.md) — cross-cutting concepts
- [doc-adr-cheatsheet.md](doc-adr-cheatsheet.md) — service catalog + ADR commands
- [sdd-flashcards.md](sdd-flashcards.md) — deep-dive Q&A on pipeline mechanics
- [VIBE-CODING.md](vibe-coding.md) — standalone commands without pipeline
