# SDD Pipeline — open-sdd

open-sdd is at `~/team/Yield/open-sdd/`.

## AGENT_INSTRUCTIONS

Load `~/team/Yield/open-sdd/agent/SDD_AGENT_INSTRUCTIONS.md` for the full pipeline protocol (gates, spec template, stack detection, etc.).

## Command mappings

When you see these patterns in the user's message, run the corresponding command with bash. DO NOT explain what you are going to do, just execute it.

| If the user says... | Run |
|---------------------|-----|
| `/f-start <args>` or "start a feature" | `~/team/Yield/open-sdd/commands/start.sh <args>` |
| `/f-plan` or "plan" | `~/team/Yield/open-sdd/commands/plan.sh` |
| `/f-implement` or "implement" | `~/team/Yield/open-sdd/commands/implement.sh` |
| `/f-implement --done N` | `~/team/Yield/open-sdd/commands/implement.sh --done N` |
| `/f-pause` or "pause" | `~/team/Yield/open-sdd/commands/pause.sh` |
| `/f-resume` or "resume" | `~/team/Yield/open-sdd/commands/resume.sh` |
| `/f-status` or "status" | `~/team/Yield/open-sdd/commands/status.sh` |
| `/f-test-design` or "design tests" | `~/team/Yield/open-sdd/commands/test-design.sh` |
| `/f-test-impl` or "implement tests" | `~/team/Yield/open-sdd/commands/test-impl.sh` |
| `/f-commit` or "commit" | `~/team/Yield/open-sdd/commands/commit.sh` |
| `/f-spec-refine` or "refine the spec" | `~/team/Yield/open-sdd/commands/refine.sh <args>` |
| `/f-resync` or "resync" | `~/team/Yield/open-sdd/commands/resync.sh` |
| `/f-resync feature/IR-70-foo` | `~/team/Yield/open-sdd/commands/resync.sh feature/IR-70-foo` |
| `/f-code-review` or "review the code" | `~/team/Yield/open-sdd/commands/code-review.sh` |
| `/f-code-review --recheck` | `~/team/Yield/open-sdd/commands/code-review.sh --recheck` |
| `/f-help` or "help" or "what's next" | `~/team/Yield/open-sdd/commands/help.sh` |
| `/f-help overview` | `~/team/Yield/open-sdd/commands/help.sh overview` |
| `/f-review-address` or "address review comments" | `~/team/Yield/open-sdd/commands/review-address.sh` |
| `/f-handoff` or "handoff" | `~/team/Yield/open-sdd/commands/handoff.sh` |
| `/f-mr` or "create the MR" | `~/team/Yield/open-sdd/commands/mr.sh` |
| `/f-close` or "close the feature" | `~/team/Yield/open-sdd/commands/close.sh` |

All commands run from the root of the current project with bash.
