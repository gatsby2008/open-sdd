---
title: <the requirement / goal being planned against>
service: <service>
date: <YYYY-MM-DD>
type: improvements
status: proposed
updated: <YYYY-MM-DD>
source: <gist URL | review | ticket | branch name>
verified_at: <commit-sha | "untracked">
---

# Goal

<What we are trying to achieve and the bar for "done" — the requirement or
standard being measured against.>

# Current State

<The honest baseline: where the code / process sits today relative to the goal.>

# Gap Analysis

<One row per gap. Verdict is ADOPT / PARTIAL / REJECT with a one-line why.>

| # | Gap | Verdict | Rationale |
|---|-----|---------|-----------|
| 1 | <gap> | ADOPT | PARTIAL | REJECT | <one-line why> |

# Plan

<Per ADOPT / PARTIAL item: the concrete change, files / skills touched, and effort.
Ordered cheapest / lowest-risk first. A checklist so any agent can see at a glance
what is left to do.>

- [ ] **<item>** — <change>. Touches `<file>`. Effort: S | M | L.
- [ ] **<item>** — <change>. Touches `<file>`. Effort: S | M | L.

<As items land, check them off and update the frontmatter: `status`
(proposed → in-progress → done; or superseded / abandoned) and `updated:`. That is how
the next agent knows where to pick up instead of redoing work.>

# Out of Scope

<What we deliberately will NOT do, and why — especially requirements rejected
because they conflict with the project's design. As important as the Plan.>

# Open Decisions

<Calls a human must make before or while executing. [TBD] if none.>

# Future Signals

<Where to pick this up next time / the reusable pointer: "If you implement this,
start with X.">
