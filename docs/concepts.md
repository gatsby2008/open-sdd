# open-sdd Concepts — Gates, Cache, Handoff, Artifacts & Stack Awareness

The load-bearing ideas the pipeline is built on. For the command-by-command flow
see [pipeline.md](pipeline.md); for installation see [setup.md](setup.md).

---

## Open Questions

**Open Questions are unresolved markdown checkboxes (`- [ ]`) in `spec.md`** (and,
optionally, in `plan.md`). They encode the pipeline's core rule:

> Never implement through ambiguity.

Unresolved Open Questions **block `/f-plan`, `/f-implement`, and `/f-handoff`**
until answered. `/f-spec` is the canonical way to draft and resolve them — feed
answers back as a file, a Jira ticket, a paste, or free text. Refine mode never
deletes user content; it resolves boxes and can add new ones.

The payoff is fewer hallucinated requirements, wrong assumptions, rework, and
scope drift — most implementation errors come from unclear requirements, not weak
models.

---

## Gates

Each gate **aborts with no writes** rather than guessing.

| Gate | Where | Rule |
|---|---|---|
| **Open Questions** | `/f-plan`, `/f-implement`, `/f-handoff` | Any unchecked `- [ ]` in `spec.md` (or `plan.md`) blocks the step |
| **Plan staleness** | `/f-implement` | If `plan.md` exists and the spec is newer, the step blocks. Staleness is tracked by **`spec_write_timestamp`** in `state.json`, not filesystem mtime (so `/f-pause`/`/f-resume` stashing can't produce false negatives). Re-run `/f-plan`, or delete `plan.md` to fall back to inline discovery |
| **Empty-MR** | `/f-mr` | Aborts on the default branch or when the branch has no commits beyond its base |

`/f-spec` also **warns** (does not block) when `plan.md` is stale or the tree has
uncommitted changes. `/f-code-review` performs a **soft test-coverage check**
(modified classes should have updated tests) and reports it — it does not hard-block
the commit.

---

## Implementation Cache

Repository memory that avoids re-discovering structure on every run.

- Initialized by `/f-start`; seeded by `/f-plan` and by `/f-spec` (when files are passed).
- Path: `.specwork/_state/<slug>-implementation-cache.json`.
- Stores: repositories, common patterns, related tests, similar classes.
- Benefit: less repo scanning, lower token consumption, faster context loading.

---

## Handoff & the Execution Pack

`/f-handoff` packages spec + rules + cache into a **model-agnostic execution
pack** at `.specwork/_handoff/<slug>-execution-pack.md` (plus `.json` metadata).
Gate: no unresolved Open Questions.

Use it when handing work to another agent (Gemini, Copilot, Codex, Claude). The
*Known Blockers* section is sourced from `_progress/escalations.md`, so an external
executor doesn't repeat failed attempts. This is what makes
`AI → Execution Pack → AI` deterministic instead of lossy.

---

## Artifacts

### Transient (`.specwork/`, gitignored)

| Path | Description |
|------|-------------|
| `_state/<slug>-state.json` | Branch metadata (branch, slug, ticket, timestamps) |
| `_state/<slug>-rules.json` | Compiled global + service rules |
| `_state/<slug>-implementation-cache.json` | Implementation memory (repositories, patterns, tests) |
| `_spec/<slug>-spec.md` | Implementation specification |
| `_spec/<slug>-source.md` | Raw input from Jira (or free text) |
| `_plan/<slug>-plan.md` | Target files, approach, risks |
| `_plan/<slug>-plan.json` | Plan metadata (progress, staleness check) |
| `_test/<slug>-test-design.md` | Designed test cases from `/f-test-design`; consumed by `/f-test-impl` (high-risk flow) |
| `_progress/escalations.md` | Append-only log of implementation escalations |
| `_review/<slug>-code-review.md` | Code review report (optional) |
| `_review/<slug>-mr-address.md` | Review comment resolution progress |
| `_handoff/<slug>-execution-pack.md` | Handoff contract (optional) |
| `_handoff/<slug>-execution-pack.json` | Handoff metadata (optional) |

### Per-project config (`.opensdd/`, committed)

| Path | Description |
|------|-------------|
| `.opensdd/service-rules.md` | Service-level invariants |

> `.specwork/` is **transient runtime state** and must never be committed —
> `/f-start` enforces this by appending it to `.gitignore` on first run. `.opensdd/`
> (the per-project config) **is** committed.

### `_progress/` — execution memory

`_progress/` is mutable runtime memory. It captures what happened during
execution: blockers, decisions, hints.

- `escalations.md` — `/f-implement` appends a dated entry whenever its escalation
  policy triggers (test loops, infrastructure failures, persistent retries).
  `/f-handoff` reads it and surfaces a *Known Blockers* section in the execution
  capsule.

---

## Stack Awareness & Frontend Support

open-sdd detects frontend projects (React, Vue, Angular, Svelte, etc.) and
adapts its heuristics. Stack detection classifies a project as:

| Detection signal | Stack | What changes |
|-----------------|-------|-------------|
| `build.gradle` / `pom.xml` | `java` | Backend JVM heuristics |
| `package.json` + Vite / Next / Angular / Svelte / Nuxt config | `frontend` | Component/page/store discovery + frontend risk signals |
| `package.json` (no frontend config) | `node` | Node backend heuristics (Express/NestJS) |
| None of the above | `unknown` | Spec-body heuristics only |

### Plan heuristics (frontend)

- **Infrastructure discovery**: searches for React error boundaries (`ErrorBoundary`, `componentDidCatch`) and Vue error handlers (`Vue.config.errorHandler`)
- **Mock consumer discovery**: searches for `*Component.tsx`, `*Page.tsx`, `*Hook.ts`, `*Store.ts` patterns alongside the existing `*Service.ts` / `*Client.ts`
- **Test resolution**: resolves `*.test.ts`, `*.test.tsx`, `*.spec.ts`, `*.spec.tsx` in `__tests__/` or sibling directories
- **Reference update**: greps `.ts`, `.tsx`, `.js`, `.jsx`, `.json` files for renamed/removed symbols

### Triage (frontend)

Frontend risk keywords: `state management`, `routing`, `accessibility`/`a11y`,
`ssr`/`hydration`, `data fetching`, `useSWR`/`react-query`, `component migration`,
`i18n`, `theming`, `dark mode`.

Frontend known layers: `component`, `page`, `store`, `hook`, `screen`, `layout`,
`util` — in addition to the standard backend layers.

### Risk signals

Frontend-specific hard keyword matches:

| Signal | Example triggers |
|--------|-----------------|
| `component-api` | props interface change, prop rename/removal, render signature change |
| `state-management` | redux/zustand/context migration, store refactor |
| `accessibility` | a11y, ARIA, keyboard nav, focus trap, WCAG |
| `routing` | react-router, useRouter, navigate, route restructure |
| `data-fetching` | tanstack query, useSWR, Apollo, SSR/hydration |
| `ui-migration` | design system update, UI library upgrade, theming overhaul |

### Test implementation

The HARD RULES table in `/f-test-impl` shows both Java (AssertJ/Mockito) and
frontend (Jest/Vitest/RTL) assertion examples side by side. FORBIDDEN patterns
are shown for both stacks.

### Code review

Frontend diff gets targeted pack hints:
- **Lifecycle hooks**: cleanup and dependency arrays
- **State management**: immutability and re-render scope
- **Memoization**: dependency correctness
- **Accessibility**: ARIA patterns and keyboard navigation
- **Routing**: side effects, guards, error states
- **Dynamic imports**: loading states, bundle splitting

### Spec template

The spec template ships with optional frontend sections. Delete the ones that
don't apply for backend-only features:

```
## UI / Component Breakdown
## User Flows
## Visual / Design Requirements
## Accessibility Requirements
## State Management
## API Contract (Frontend Perspective)
```

---

## Reverting a Failed Implementation

You reach the pre-`/f-commit` review, see the implementation is wrong, and want to
**discard the code changes but keep the pipeline state** (`.specwork/`) so you can
re-spec and re-implement.

Use **`/f-undo`** — it discards the changes while preserving `.specwork/`:

```bash
/f-undo            # reversible: stash the implementation
/f-undo --restore  # changed your mind — bring it back (redo)
/f-undo --hard     # irreversible discard (asks you to re-run with --force)
```

`/f-close` does the *opposite* (wipes `.specwork/`, leaves the code), so it is not
the tool here.

### What `/f-undo` does under the hood (manual fallback)

The safety net is that **`.specwork/` is gitignored** (`/f-start` enforces it), so
it never enters a stash and `git clean -fd` skips it — only `git clean -fdx` would
remove ignored files. At this point all changes are uncommitted: modified classes
are *tracked*, new classes/tests from `/f-implement` are *untracked but not
ignored*. The reversible default is a stash; by hand:

```bash
git clean -fdn                       # DRY RUN — list what would be deleted; nothing removed
git stash push --include-untracked   # reversible: stash code changes (.specwork/ stays)
# …or, to discard irreversibly:
git restore . && git clean -fd       # revert tracked edits + delete new files
git status --ignored --short         # confirm only .specwork/ remains
```

Then re-spec from the preserved state:

```bash
/f-spec <correction / new context>   # refine the spec (resolve/append Open Questions)
/f-plan                              # re-run: spec is now newer than plan (stale gate)
/f-implement
```

`state.json`, `rules.json`, `implementation-cache.json`, and `source.md` are
untouched, so only the failed implementation is discarded. Remember the **plan
staleness gate**: after `/f-spec`, an existing `plan.md` blocks `/f-implement`
until `/f-plan` is re-run (or the plan is deleted).

---

## Fixes vs. the original SDD

open-sdd corrects several bugs from the pipeline it reimplements:

| Bug | Fix |
|-----|-----|
| mtime gate false negative after git stash (f-pause destroys mtime) | `spec_write_timestamp` stored in `state.json`, not filesystem mtime |
| Java-only heuristics silently skip Node/TS projects | Stack detection (`build.gradle`/`pom.xml` → java, `package.json` + frontend config → frontend, `package.json` only → node) with per-stack heuristics |
| `resolve_slug()` ignored free-text slug in favor of branch name | Matches current branch against `state.json::branch` field first |