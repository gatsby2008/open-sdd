# open-sdd

Open-source Spec-Driven Development pipeline. Framework-agnostic, LLM-agnostic.

Portable reimplementation of the SDD pipeline — originally built for Claude Code, now decoupled to work with any LLM (Ollama, GPT, Claude, Gemini) or purely as shell scripts.

## What it does

Guides a feature from ticket to merge request using strict gates:

```
/start <ticket-or-text>  →  /plan (optional)  →  /implement  →  /commit  →  /mr  →  /close
```

## Structure

```
open-sdd/
├── agent/
│   └── SDD_AGENT_INSTRUCTIONS.md   # System prompt for any LLM
├── lib/
│   ├── gates.sh                     # Validation gates (fixed: no mtime fragility)
│   ├── metrics.sh                   # Timing & token metrics
│   └── jira.sh                      # Jira REST client (curl, env vars)
├── commands/
│   ├── start.sh                     # Branch + spec scaffold
│   ├── plan.sh                      # Discovery + plan
│   ├── implement.sh                 # Gates + implementation loop
│   ├── commit.sh                    # Semantic commit
│   ├── mr.sh                        # MR description + push
│   └── close.sh                     # Clean .specwork/
└── templates/
    ├── spec.md
    ├── rules.json
    └── mr-config.json
```

## Fixed from original

| Bug | Fix |
|-----|-----|
| mtime gate false negative after f-pause/resume (git stash destroys mtime) | spec_write_timestamp stored in state.json; plan compared against that |
| `source metrics.sh` blocked by allowed-tools | No permission system — scripts run directly |
| Java-only heuristics silent on TS/Node projects | Stack detection + per-stack fallback |
| Metrics "heavy" tier mislabeled | Prompt and code agree on which skills are heavy |

## Usage

```bash
# With Ollama:
cat agent/SDD_AGENT_INSTRUCTIONS.md | ollama run llama3

# With any LLM:
cp agent/SDD_AGENT_INSTRUCTIONS.md to your system prompt

# Script-only (no LLM):
./commands/start.sh "JIRA-123 fix NPE in lead processing"
```

## License

MIT
