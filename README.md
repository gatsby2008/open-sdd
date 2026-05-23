# open-sdd

Open-source Spec-Driven Development pipeline. Framework-agnostic, LLM-agnostic.

A portable reimplementation of the SDD pipeline — originally built for Claude Code,
now decoupled to work with any LLM (Ollama, GPT, Claude, Gemini) or purely as shell scripts.

## Pipeline

```
start.sh "ticket or text"  →  plan.sh (optional)  →  implement.sh  →  commit.sh  →  mr.sh  →  close.sh
```

Each command enforces gates (Open Questions, plan staleness, required artifacts),
ensuring you never skip a step.

## Commands

| Command | When to run | What it does |
|---------|-------------|--------------|
| `start.sh <ticket or text>` | New feature | Creates feature branch or selects working branch; fetches Jira ticket if applicable; writes spec scaffold + `state.json` with `spec_write_timestamp` |
| `plan.sh` | After spec is ready (optional for small changes) | Resolves slug; checks Open Questions gate; detects stack (java/node/unknown); discovers target files via heuristics (infra, mock consumers, ref grep); risk assessment; writes `plan.md` + `plan.json`; updates implementation cache |
| `implement.sh` | After plan (or direct) | Loads spec + plan; enforces gates; displays context; supports `--done N` to mark files complete and update plan.json progress |
| `commit.sh` | After implementing | Stages tracked changes; generates semantic commit message from spec title + optional ticket ref; accepts/edits/aborts; updates state.json with commit SHA |
| `mr.sh` | After commit | Pushes branch; generates MR body from spec + plan; creates/updates PR via `gh` (GitHub CLI); stores MR URL in state.json |
| `close.sh` | After MR merge | Verifies MR merge status (via `gh`); deletes `.specwork/`; optionally deletes feature branch |

## Implement workflow

During implementation, the LLM (or developer) works through target files one at a time:

```bash
./commands/implement.sh          # Show spec, plan, first target
# ... edit code ...
./commands/implement.sh --done 1 # Mark file 1 complete
# ... edit code ...
./commands/implement.sh --done 2 # Mark file 2 complete
./commands/commit.sh             # Commit all changes
```

## Structure

```
open-sdd/
├── agent/
│   └── SDD_AGENT_INSTRUCTIONS.md   # System prompt for any LLM
├── lib/
│   ├── gates.sh                     # Validation gates (fixed: no mtime fragility)
│   ├── metrics.sh                   # Timing & token metrics (opt-in: CLAUDE_LOG_METRICS=true)
│   └── jira.sh                      # Jira REST client via curl + env vars
├── commands/
│   ├── start.sh                     # Branch + spec scaffold
│   ├── plan.sh                      # Stack-aware discovery + plan
│   ├── implement.sh                 # Gates + per-file implementation loop
│   ├── commit.sh                    # Semantic commit
│   ├── mr.sh                        # MR via gh (GitHub, not GitLab)
│   └── close.sh                     # Clean .specwork/, delete branch
└── templates/
    ├── spec.md
    ├── rules.json
    └── mr-config.json
```

## Bugs fixed from the original (claude-tools)

| Bug | Fix |
|-----|-----|
| mtime gate false negative after git stash (f-pause destroys mtime) | `spec_write_timestamp` stored in `state.json`, not filesystem mtime |
| `source metrics.sh` blocked by Claude Code allowed-tools | No permission system — scripts run directly |
| Java-only heuristics silently skip Node/TS projects | Stack detection (`build.gradle`/`pom.xml` → java, `package.json` → node) with per-stack heuristics |
| Metrics "heavy" tier mislabeled | Prompt and code now agree on which skills are heavy |
| `resolve_slug()` ignored free-text slug in favor of branch name | Matches current branch against `state.json::branch` field first |

## Usage

```bash
# With Ollama:
cat agent/SDD_AGENT_INSTRUCTIONS.md | ollama run llama3

# With any LLM — paste the contents of SDD_AGENT_INSTRUCTIONS.md
# as your system prompt, then run commands with:
./commands/start.sh "JIRA-123 fix NPE in lead processing"

# Script-only (no LLM):
./commands/start.sh "JIRA-123 fix NPE in lead processing"
# ... edit spec ...
./commands/plan.sh
./commands/implement.sh
./commands/commit.sh
```

## Requirements

- Bash 4+
- `git`, `stat`
- `gh` (GitHub CLI) — required only for `mr.sh`
- `jq` — optional, for Jira integration
- `JIRA_EMAIL`, `JIRA_TOKEN`, `JIRA_DOMAIN` — required only for Jira ticket fetching

## License

MIT
