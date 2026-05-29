# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

open-sdd is the **implementation** of a Spec-Driven Development (SDD) pipeline —
a framework-agnostic, LLM-agnostic toolchain that drives a feature from a Jira
ticket (or free text) through spec → plan → implement → commit → MR → close.
Working here means editing the pipeline tool itself, not consuming it. (The
pipeline's own `/f-*` skills are available in this session and can be dogfooded,
but the source of truth for behavior is the scripts in `commands/` and `engine/`.)

`README.md` is the user-facing manual for the pipeline. Read it for the full
command catalog, artifact layout, and flow diagram before changing
user-observable behavior.

## Commands

```bash
# Full test suite (mirrors CI in .github/workflows/test.yml)
python3 -m unittest discover -s tests -p 'test_*.py' -v   # unit suite
bash tests/smoke.sh                                        # end-to-end smoke in scratch git repos

# Single unit test module / case
python3 -m unittest tests.test_gates
python3 -m unittest tests.test_gates.TestOpenQuestions.test_unresolved_blocks

# Run the engine directly (what the shell wrappers call under the hood)
PYTHONPATH=. python3 -m engine.cli <command> [args...]
PYTHONPATH=. python3 -m engine.cli resolve-slug
PYTHONPATH=. python3 -m engine.cli implement-check <slug>

# Run a pipeline command script directly (each is self-contained)
./commands/start.sh <ticket-or-text> [--branch <name> | --keep]
./commands/implement.sh
./commands/implement.sh --done N

# Install /f-* commands into opencode (regenerates ~/.config/opencode/commands)
./install.sh
```

There is no build step and no package manager — the engine is plain stdlib
Python 3 (CI uses `3.x`; tests import-guard for 3.9). `pytest` is vendored in
`.venv/` but tests are written as `unittest` and CI runs them with `unittest`.

## Architecture

The pipeline is a **two-layer system**: thin bash orchestrators over a Python
decision engine.

### `commands/*.sh` — orchestration layer
One script per `/f-*` command. Each script:
- Resolves `ENGINE_ROOT` from its own location and defines
  `engine() { PYTHONPATH="$ENGINE_ROOT" python3 -m engine.cli "$@"; }`.
- Calls the engine for every **decision** (gates, slug resolution, plan state)
  and handles only **I/O and interaction** (printing, prompts, `git`, `gh`/`glab`).
- Is independently runnable and self-gating — there is **no state machine**.
  Each command checks its own artifact preconditions (e.g. `implement.sh` calls
  `engine precheck` then `engine implement-check`) and aborts if they aren't met.

### `engine/` — decision layer (pure Python, no side effects on git)
- `cli.py` — single dispatch entry point. `COMMANDS` lists every subcommand;
  `dispatch` maps the implemented ones to `cmd_*` handlers. Subcommands print
  machine-readable tokens to stdout/stderr (`SPECWORK_OK`, `GATES_PASSED`,
  `UNRESOLVED_OQS`, `PLAN_STALE`, JSON payloads) that the bash layer greps on.
  `FLOW_MAP` and `triage()` classify ticket complexity — **advisory only**, never
  enforced.
- `gates.py` — all preconditions: `resolve_slug`, `require_specwork`,
  `check_open_questions`, `check_plan_staleness`, `check_required_artifacts`,
  `detect_stack`, plus risk/consistency heuristics for spec analysis.
- `state.py` — `PipelineState` dataclass + load/save. Its `extra` field
  **preserves unknown on-disk keys** across saves (legacy `id`, `input_type`,
  etc.); `from_dict`/`to_dict` round-trip them deliberately. Don't drop them.
- `persistence.py` — typed read/write helpers for each artifact file under
  `.specwork/`. The implementation cache lives in its **own** file, never inside
  `state.json`.

### `.specwork/` — transient runtime state (gitignored)
Per-feature artifacts keyed by `<slug>`: `_state/` (state.json, rules.json,
cache, path.json), `_spec/` (spec.md, source.md), `_plan/` (plan.md, plan.json),
`_test/`, `_review/`, `_handoff/`, `_progress/`. Never commit these. The
permanent outputs are git commits, optionally a published spec under
`docs/specs/`, and ADRs.

### `.opensdd/` — per-project config (committed)
`service-rules.md` (service invariants) and `mr-config.json` (MR target branch /
merge strategy). In *this* repo `.opensdd/service-rules.md` exists because
open-sdd dogfoods itself.

## Conventions and invariants

- **Slug resolution drives everything.** A slug is derived from the current git
  branch, but `resolve_slug()` first matches the branch against the `branch`
  field inside each `*-state.json` so renamed/prefixed branches still resolve.
  Most commands fail loudly with `COULD_NOT_RESOLVE_SLUG` outside a branch with
  state.

- **Staleness is timestamp-based, not mtime-based.** `check_plan_staleness`
  compares plan mtime against `spec_write_timestamp` stored in `state.json`
  (not the spec file's filesystem mtime) — because `/f-pause` stashes destroy
  mtimes. Any command that writes the spec must bump that timestamp
  (`engine bump-spec-ts`).

- **Open Questions gate.** Unresolved `- [ ]` checkboxes under an
  `## Open Questions` heading in `spec.md` (or `plan.md`) hard-block
  `/f-implement` and `/f-handoff`. The parser is section-scoped — keep that
  heading exact.

- **Plan is optional.** `implement.sh` runs a "no-plan workflow" (inline
  discovery from the spec) when `plan.json` is absent; staleness only applies
  when a plan exists. Don't make a plan mandatory.

- **Stack detection** (`detect_stack`): `build.gradle`/`pom.xml` → `java`,
  `package.json` → `node`. `commands/check.sh` is the stack-detecting validation
  gate run by `/f-commit` and `/f-mr`; projects can override it with a local
  `commands/check.sh`.

- **No permission/allowed-tools system.** Scripts run directly — this is a
  deliberate fix for the original Claude-Code-coupled version. Don't reintroduce
  `source`-gating assumptions.

- **install.sh is the source of truth for the command catalog.** Adding a new
  `/f-*` command means: add `commands/<name>.sh`, register it in `install.sh`,
  wire any new engine subcommand into `cli.py`'s `COMMANDS` + `dispatch`, and
  keep `FLOW_MAP` / README / `templates/CLAUDE.md` consistent.

## When changing behavior

- The bash↔engine contract is the printed tokens. If you change a token string
  the engine emits, update every `case`/`grep` in `commands/*.sh` that matches it.
- `templates/` holds scaffolds copied into consumer projects (`AGENTS.md`,
  `CLAUDE.md`, `spec.md`, `rules.md`, `service-rules.md`, `*.json`). Editing a
  template changes what new consumer projects get — it does **not** retroactively
  update this repo's own files.
- `agent/SDD_AGENT_INSTRUCTIONS.md` is the system prompt every installed `/f-*`
  command tells the LLM to read first. Keep it aligned with actual gate behavior.
- Add/extend tests in `tests/` for any gate or engine change, and extend
  `tests/smoke.sh` for any change to a command script's contract.
