---
title: <one-line problem statement>
service: <service>
date: <YYYY-MM-DD>
type: bug
source: <branch name | "pasted code">
verified_at: <commit-sha | "untracked">
---

# Problem

<One sentence: what was wrong, surprising, or unclear.>

# Symptoms

- <Observable signal that started the dig>
- <Another signal — logs, wrong results, errors>

# Reproduction

<How to trigger the bug — exact steps, request, input, or conditions. Concrete enough
that another agent can confirm it is the same bug before changing anything. [TBD] if it
could not be reproduced; say what makes it intermittent.>

# Investigation

<What was checked: classes, services, files, logs, dashboards. Quote the queries and
code that were actually used, verbatim, in fenced blocks.>

```sql
-- the query used, exactly as run
```

# Findings

<The factual discoveries — what is now known to be true about the system.>

# Root Cause

<The underlying cause the findings point to. [TBD] if not yet established.>

# Fix

**Status:** applied | proposed | none-yet
**Where:** `path/to/File.ext` → `methodOrSymbol()` — the precise location(s) to change
**Change:** <the concrete edit, specific enough to implement without re-deriving it; show before → after when known>
**Verify:** <how to confirm it works — a test to run, a command, or an observable signal>

<Use `[TBD]` in any field not yet known. If Status is `applied`, point to the commit / MR; if `proposed`, this is the recommended change for the next agent to make.>

# Related Classes

- <Class / file / component implicated>
- <...>

# Future Signals

<The reusable heuristic for next time: "If you see X again, check Y first.">
