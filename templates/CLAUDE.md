# SDD Pipeline — open-sdd

open-sdd is at `~/team/Yield/open-sdd/`.

## Available commands

| Chat | Description |
|------|-------------|
| `/f-start <text or JIRA-123>` | Create branch + write source.md (spec.md is created by /f-spec) |
| `/f-plan` | Discover files, assess risks, write plan |
| `/f-implement` | Show spec + plan + first target |
| `/f-implement --done N` | Mark target N as complete |
| `/f-pause` | Pause current pipeline and stash all work |
| `/f-resume` | List paused pipelines and restore selected one |
| `/f-status` | Show current pipeline state |
| `/f-test-design` | Design test cases for current changes |
| `/f-test-impl` | Implement test files |
| `/f-commit` | Stage + semantic commit |
| `/f-spec` | Draft the spec (first call) or refine it (subsequent calls) |
| `/f-spec <context>` | Same, with extra context (files, jira, text) |
| `/f-spec-refine <context>` | Deprecated — alias for `/f-spec <context>` |
| `/f-resync` | Resync pipeline after branch rename |
| `/f-resync <new-branch>` | Rename branch and resync (atomic) |
| `/f-code-review` | Quality/security review of current diff |
| `/f-code-review --recheck` | Re-review comparing against previous report |
| `/f-help` | Show pipeline state and next step |
| `/f-help overview` | Full pipeline reference |
| `/f-mr-address` | Address MR review comments one by one |
| `/f-handoff` | Generate execution pack for another agent/model |
| `/f-mr` | Push + create MR on GitHub |
| `/f-close` | Delete `.specwork/`, optionally delete branch |

## Usage

When I run `/f-start`, execute `~/team/Yield/open-sdd/commands/start.sh`.
When I run `/f-plan`, execute `~/team/Yield/open-sdd/commands/plan.sh`.
And so on for each command.

All commands run from the root of the current project.
