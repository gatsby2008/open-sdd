# Why open-sdd instead of claude-tools/sdd?

This document explains the value of `open-sdd` relative to `claude-tools/sdd`
based on the **current state** of both repos (not historical snapshots).

## Short answer

`open-sdd` is useful when you want:

- a repository-native command implementation (`commands/*.sh`) that runs
  directly in the project,
- a compact Python engine (`engine/`) that centralizes gates and decision logic,
- stronger parity checks for command/install surface in CI,
- an explicitly model-agnostic packaging flow for non-Claude clients.

`claude-tools/sdd` is useful when you want:

- skill-driven distribution through `~/.claude/skills/sdd`,
- a richer skill catalog in one package (pipeline + doc/adr/query helpers),
- deep skill-level guidance for Claude-style orchestration.

Both are production-capable and now share many core capabilities.

## Reality check: both projects now have broad parity

Older comparisons that said “claude-tools lacks X” are no longer true for many
features. Today, **both** include:

- `/f-auto` and `SDD_NON_INTERACTIVE` mode,
- `/f-pause` + `/f-resume`,
- `/f-handoff`,
- risk signals and triage/path classification,
- doc/ADR/query command families (`doc-*`, `adr-*`),
- automated tests.

So the decision is less “feature exists vs does not exist” and more
“where the behavior is implemented and how it is distributed”.

## What open-sdd still does differently

### 1) Repo-local command runtime

`open-sdd` centers execution in local shell commands under `commands/`.
That makes behavior inspectable and patchable from inside the target repo
without depending on global skill installation layout.

### 2) Engine-first command wiring

`open-sdd` wrappers call `python3 -m engine.cli ...` subcommands (e.g.
`precheck`, `implement-check`, `implement-plan`, `risk-signals`,
`resolve-slug`, `bump-spec-ts`) and key on machine-readable outcomes.

This tends to reduce ad-hoc parsing in command scripts and keeps gate logic in
one place.

### 3) Strong parity guardrails in this repo

`open-sdd` includes explicit parity checks in `tests/`:

- `tests/check-install-parity.sh`
- `tests/check-sdd-surface-parity.sh`

These guard drift between documented/installed command surfaces.

### 4) Explicit open-sdd packaging for model-agnostic use

`open-sdd` ships a standalone pipeline package (`agent/PIPELINE.md`,
repo installer flow), while `claude-tools/sdd` is primarily a skill bundle
inside `claude-tools`.

## Current quantitative snapshot (local verification)

These numbers are intentionally concrete and should be updated when they drift.

- `open-sdd`:
  - `commands/`: 30 scripts
  - Python unit tests: 108 (`python3 -m unittest discover -s tests -p 'test_*.py'`)
- `claude-tools/sdd`:
  - SDD skill modules under `contrib/skills/sdd`: 34 entries
  - SDD unit tests: 170 (`python3 -m unittest discover -s contrib/skills/sdd/lib/tests -p 'test_*.py'`)

## Capability parity map

| Capability | open-sdd | claude-tools/sdd | Notes |
|---|---|---|---|
| Pipeline entry (`/f-start`) | ✅ | ✅ | Both initialize `.specwork` artifacts. |
| Spec lifecycle (`/f-spec`) | ✅ | ✅ | Draft + refine flows in both. |
| Planning (`/f-plan`) | ✅ | ✅ | Both support optional plan-first flow. |
| Implementation (`/f-implement`) | ✅ | ✅ | Both enforce OQ/staleness style gates. |
| Auto mode (`/f-auto`) | ✅ | ✅ | Both support non-interactive orchestration with gates. |
| Non-interactive state (`SDD_NON_INTERACTIVE`) | ✅ | ✅ | Persist/rehydrate behavior exists in both (current state). |
| Pause / resume (`/f-pause`, `/f-resume`) | ✅ | ✅ | Context switch supported in both. |
| Handoff (`/f-handoff`) | ✅ | ✅ | Execution-pack style handoff supported in both. |
| MR flow (`/f-mr`, `/f-mr-address`) | ✅ | ✅ | Both include MR generation/update paths. |
| Risk signals | ✅ | ✅ | Deterministic signal detection present in both. |
| Triage / path classification | ✅ | ✅ | Both produce path/tier guidance. |
| Doc/ADR/query ecosystem | ✅ | ✅ | `doc-*`, `adr-*` in both ecosystems. |
| Repo-local command scripts | ✅ (primary) | ⚠️ (skill-driven) | open-sdd centers on `commands/*.sh`; claude-tools centers on skill docs + libs. |
| Surface parity checks in-repo | ✅ | ⚠️ | open-sdd includes explicit parity check scripts in `tests/`. |
| Distribution model | Standalone package | Central skill distribution | Different operating model more than capability gap. |

## Recovery workflow (`/undo` without losing pipeline state)

Practical recovery details are documented in
[`sdd-pipeline-cheatsheet.md`](sdd-pipeline-cheatsheet.md) under
**Recovery: undo/redo with opencode**. Keeping that flow in one place avoids
duplicating command-level recovery guidance across docs.

## Practical selection guide

Choose **open-sdd** when:

- you want repo-local command control and easy patching in the project itself,
- you want built-in surface parity checks in the same repo,
- your team is standardizing on the open-sdd package flow across multiple LLM clients.

Choose **claude-tools/sdd** when:

- your org already uses `claude-tools` as the global distribution mechanism,
- you want all SDD + doc/adr/query skills centrally managed in one skill pack,
- your workflow is anchored in Claude skill orchestration.

## Token savings: does open-sdd save tokens?

Short answer: **potentially yes**, but the gain comes from execution model, not from provider lock-in.

- `open-sdd` is model-agnostic and can run with Claude API too.
- Token savings happen when deterministic checks are executed by scripts/engine
  (precheck, slug resolution, staleness, risk-signal detection) instead of being
  repeatedly reasoned through long conversational turns.
- If both setups run equivalent scripted gates and keep prompts tight, token cost
  can be similar. Savings are largest when replacing “LLM decides by rereading artifacts”
  with “command returns machine-readable result”.

In other words: using Claude API does **not** negate open-sdd’s token-efficiency
benefits; what matters is how much logic is pushed into deterministic tooling.

### Token hotspots (practical view)

| Phase / command | Typical token cost | Why it costs | How to reduce |
|---|---|---|---|
| `/f-spec` draft/refine | High | Generates/edits long structured spec text. | Keep input context scoped; avoid redundant re-refines with no new data. |
| `/f-plan` on large repos | Medium–High | Discovery + plan synthesis over many candidate files. | Run after clear scope; keep `Implementation Context` precise; avoid broad ambiguity. |
| `/f-implement` (multi-pass) | High | Code generation + retries + inline validations. | Keep steps focused; use plan targets; avoid unrelated refactors in same pass. |
| `/f-test-design` + `/f-test-impl` | High | Additional design + test code generation cycles. | Run only when risk gate justifies it. |
| `/f-code-review` | Medium–High | Summarization and issue reasoning over diffs/files. | Review scoped diffs; split very large changes into smaller commits. |
| Deterministic gates (`precheck`, staleness, slug, risk-signals) | Low | Scripted checks, minimal LLM reasoning. | Prefer command outputs over conversational re-analysis. |

Rule of thumb: the largest savings come from reducing repeated semantic
generation loops (`/f-spec`, `/f-plan`, `/f-implement`) and maximizing
deterministic gate usage between those loops.

Related playbooks:

- Spanish checklist: [`../playbooks/token-efficiency-checklist-es.md`](../playbooks/token-efficiency-checklist-es.md)
- English checklist: [`../playbooks/token-efficiency-checklist-en.md`](../playbooks/token-efficiency-checklist-en.md)

## Final note

Treat this as a living comparison. If command counts, test counts, or behavior
contracts change, update this file together with the corresponding tests/docs so
the comparison stays factual.
