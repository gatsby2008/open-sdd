# open-sdd — Agent Guide

## Quick reference

| What | How |
|------|-----|
| **Run full test suite** | `python3 -m unittest discover -s tests -p 'test_*.py' -v` |
| **Run smoke tests** | `bash tests/smoke.sh` |
| **Single unit test** | `python3 -m unittest tests.test_gates -v` |
| **Install / re-register commands** | `bash install.sh` (writes `~/.config/opencode/commands/f-*.md`) |
| **Engine CLI** | `PYTHONPATH=. python3 -m engine.cli <command>` |
| **No Jira needed** | free text works — just pass a description instead of a ticket |

## Architecture

**open-sdd is a Spec-Driven Development pipeline** — portable, LLM-agnostic (works with Claude, GPT, Gemini, Ollama). It lives entirely in this repo; consumers clone it and run `install.sh`.

### Three layers

1. **Bash commands** (`commands/*.sh`) — each script prints context + instructions; the LLM reads the output and takes action (write files, ask user, run git commands)
2. **Python engine** (`engine/`) — validated logic (gates, state, worktree, triage, branch detection). Called by bash scripts via `python3 -m engine.cli`
3. **Agent instructions** (`agent/PIPELINE.md`) — the full protocol. Loaded globally via `opencode.json` `instructions`

### State vs config

| Path | Gitignored? | Contents |
|------|-------------|----------|
| `.specwork/` | **Yes** (enforced by `/f-start`) | Transient pipeline state: spec, plan, source, cache, escalations |
| `.opensdd/` | **No** (committed) | Per-dev config: `service-rules.md`, `mr-config.json` |

### Pipeline is artifact-driven (no state machine)

Each command independently checks preconditions:
- Missing `.specwork/` → run `/f-start`
- Missing spec.md → `/f-start` created source.md, now run `/f-spec`
- Unresolved Open Questions → resolve before `/f-plan` or `/f-implement`
- Stale plan → re-run `/f-plan`
- Clean tree after commits → run `/f-mr`

**Never chain commands automatically** — after each command, stop and present the result.

### Companion commands (no pipeline needed)

| Command | Script | Use |
|---------|--------|-----|
| `/f-commit` | `commit.sh` | Standalone — semantic commit on any branch |
| `/f-mr` | `mr.sh` | Standalone — MR creation |
| `/f-code-review` | `code-review.sh` | Standalone — quality + security review of your diff |
| `/f-undo` | `undo.sh` | Standalone — discard reversibly (`--restore` to recover, `--hard --force` to purge) |
| `/doc-catalog` | `doc-catalog.sh` | Scan project, generate `docs/service-info.md` |
| `/doc-publish` | `doc-publish.sh` | Publish catalog to central registry |
| `/doc-query` | `doc-query.sh` | Cross-service architecture questions |
| `/doc-adr` | `doc-adr.sh` | Architecture Decision Record |
| `/doc-investigation` | `doc-investigation.sh` | Capture investigation as structured document |
| `/doc-investigation-query` | `doc-investigation-query.sh` | Query across all captured investigations |

### Registries (all under `$OPEN_SDD_DOC_HOME/${OPEN_SDD_ROOT:-$HOME}/.opensdd/registry/`)

- `service-catalog/` — `/doc-publish`
- `adr-registry/` — `/adr-publish`
- `spec-registry/` — `/spec-publish` or `/f-mr`
- `investigation-registry/` — `/doc-investigation`

### Stack detection

`resolve_slug` reads `state.json::branch` first, falls back to deriving from current branch name. `detect_stack` checks `pom.xml`/`build.gradle` (java), `package.json` + framework config (frontend/next/vue/react), `package.json` only (node backend), else unknown.

### Key conventions

- Open Questions format: `- [ ] **#N** <question>`; resolved → `- [x]` with appended ` — resolved: <answer>`. Numbering is append-only, never reused
- Clickable paths: `` `/absolute/path/file:42` `` with line number
- `triage.sh` is **internal** — run by `/f-spec` draft mode, never standalone
- Spec headings must be exact (templates/spec.md is authoritative)
- Risk signals: `db-migration`, `auth-security`, `breaking-api`, `data-destructive`, `concurrency` (backend); `component-api`, `state-management`, `accessibility`, `routing`, `data-fetching`, `ui-migration` (frontend)
- Jira: `lib/jira.sh`, env vars `JIRA_BASE_URL`, `JIRA_USER`, `JIRA_TOKEN`
- GitLab: install `glab`; GitHub: install `gh`
- Non-interactive mode: set `SDD_NON_INTERACTIVE=1`
- Service name resolver: `lib/service-name.sh` → `resolve_service_name()` (spring app name > docs/service-info.md > git repo basename > "unknown")
