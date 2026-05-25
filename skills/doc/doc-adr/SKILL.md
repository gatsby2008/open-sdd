---
name: doc-adr
description: Create an Architecture Decision Record (ADR) for a technical decision. Use when a significant technical choice was made — library selection, infrastructure trade-off, pattern adoption, security approach — and the reasoning should be preserved in the codebase.
argument-hint: "brief description of the decision, e.g. 'use PostgreSQL instead of Redis for circuit breaker state'"
allowed-tools: Read, Write, Bash(find docs:*), Bash(find .specwork:*), Bash(cat .specwork/_spec/*), Bash(ls:*), Bash(mkdir:*), Bash(git rev-parse:*), Bash(git branch:*), Bash(git add:*), Bash(git commit:*), mcp__atlassian__getJiraIssue
---

# ADR

**Load**: `view ~/.claude/skills/doc/doc-adr/SKILL.md`

---

## Description

Captures a technical decision as an Architecture Decision Record (ADR) — a short,
immutable document that records the context, the decision, and the consequences.

ADRs never get edited. If a decision changes, a new ADR supersedes the old one.
This gives the team a permanent, searchable history of *why* the system is the way it is.

---

## Use Cases

- `/doc-adr` — prompts for the decision interactively
- `/doc-adr "use PostgreSQL instead of Redis for circuit breaker state"` — starts with a description
- `/doc-adr MYYES-17097` — fetches the Jira ticket and extracts decisions from it
- `/doc-adr open-questions` — extracts resolved Open Questions from the current branch spec and generates ADRs from them

---

## What It Does

| Step | Action |
|------|--------|
| 1 | Reads `$ARGUMENTS` — decision description, ticket ID, or nothing |
| 2 | If ticket ID → fetches via Jira MCP to extract context (see Jira Mode) |
| 3 | If missing context → asks targeted questions (see Context Gathering) |
| 4 | Scans `docs/adr/` to determine the next ADR number |
| 5 | Generates a slug from the title |
| 6 | Creates `docs/adr/` if it does not exist |
| 7 | Writes the ADR to `docs/adr/ADR-NNN-<slug>.md` |
| 8 | Prints the ADR and asks for confirmation before writing |
| 9 | On confirmation, writes the file |
| 10 | Offers to commit |

---

## Context Gathering

Before drafting, the skill needs four things:

| What | Question asked if missing |
|------|--------------------------|
| **The decision** | "What was decided?" |
| **The context** | "What problem or constraint forced this decision?" |
| **Alternatives** | "What other options were considered and why were they ruled out?" |
| **Consequences** | "What are the trade-offs — what do you gain and what do you give up?" |

If `$ARGUMENTS` provides enough to infer some of these, do not ask — fill them in
and note any inferences as `[INFERRED]` in the draft for the user to confirm.

Ask all missing questions in a single message, not one at a time.

---

## Open Questions Mode

Triggered when `$ARGUMENTS` is `open-questions`.

1. Reads current branch → extracts ticket ID or slug
2. Locates `.specwork/_spec/<id>-spec.md` — aborts if missing
3. Scans `## Open Questions` for resolved items (`- [x]`):

```
- [x] Consent timeout duration — resolved: 30 minutes, confirmed with Legal
- [x] Retry on Access Denied — resolved: no retry, open circuit immediately
```

4. Filters out trivial resolutions (e.g. "confirmed by PM", "no change needed") —
   only surfaces decisions that have architectural consequences.

5. For each non-trivial resolved question, show:

```
Resolved Open Questions that may warrant an ADR:

  1. Consent timeout: 30 minutes confirmed with Legal
     → involves a compliance constraint and a timeout window lifecycle decision

  2. No retry on Access Denied — open circuit immediately
     → affects error handling strategy across all TLO callers

Generate ADRs for which? (comma-separated numbers, 'all', or 'none'):
```

6. For each selected question, run the normal ADR draft flow using the question
   text and resolution as the starting context.

---

## Jira Mode

If `$ARGUMENTS` matches `^[A-Z]+-[0-9]+$`, fetch the ticket via
`mcp__atlassian__getJiraIssue`. Extract:

- Decisions embedded in the description or comments
- Alternatives mentioned and reasons for rejection
- Risks or assumptions that represent consequences

If multiple distinct decisions are found in the ticket, list them and ask:

```
Found 3 decisions in MYYES-17097. Which should this ADR cover?

  1. Use PostgreSQL instead of Redis for circuit breaker state
  2. Pessimistic write lock on open() to prevent race conditions
  3. Singleton row pattern (id=1) instead of append-only log

Enter a number, or 'all' to create one ADR per decision:
```

If `all`: create each ADR sequentially, incrementing the number for each.

---

## Numbering and File Name

Scan `docs/adr/` for files matching `*-ADR-NNN-*.md`:

```bash
find docs/adr -name "*-ADR-[0-9][0-9][0-9]-*.md" \
  | grep -oE 'ADR-[0-9]{3}' \
  | sort \
  | tail -1
```

Extract the highest number and increment by 1. If no ADRs exist yet, start at `ADR-001`. Zero-padding to 3 digits means lexical sort equals numeric sort.

Zero-pad to 3 digits: `ADR-001`, `ADR-012`, `ADR-100`.

**File name format**: `<TICKET>-ADR-NNN-<slug>.md`

The ticket ID comes first, followed by `ADR-NNN`, then the kebab-case slug. Resolve the ticket from `$ARGUMENTS`, the current branch name, or context inference:

```
MYYES-17097-ADR-001-use-postgresql-circuit-breaker.md
IR-36-ADR-002-defer-pii-until-consent-accepted.md
```

If no ticket ID is available, use the literal prefix `NOTICKET`:

```
NOTICKET-ADR-003-adopt-pessimistic-write-lock-for-circuit-open.md
```

The `NOTICKET` prefix keeps `ADR-NNN` in a fixed position (always the second hyphen-separated segment), so the find/grep numbering scan above stays uniform.

The ADR counter is **service-wide and monotonic** — it does not reset per ticket. A service whose ADRs span tickets IR-64 and IR-65 still numbers them ADR-001, ADR-002, ADR-003 in the order they were created.

---

## ADR Format

```markdown
# ADR-NNN: <Title>

## Status
Accepted

## Context
<One or two paragraphs: the problem, constraint, or situation that forced a decision.
No solution language here — only the "why we had to choose something.">

## Decision
<What was decided. Include the key reason alternatives were ruled out — one sentence
per alternative is enough.>

## Consequences
<Bullet list of trade-offs — both positive and negative. Be specific.
A vague "adds complexity" is less useful than "every TLO call now incurs one extra DB read.">

## Related
- Jira: [TICKET-ID](url)   ← omit if none
- MR: [!NNN](url)          ← omit if none
```

---

## Title Rules

- Title Case
- Start with a verb: "Use X", "Replace X with Y", "Adopt X for Y", "Disable X"
- Max 10 words
- Never start with "We decided to" or "Decision to"

Good: `Use PostgreSQL Instead of Redis for Circuit Breaker State`
Bad: `Decision about circuit breaker persistence layer`

---

## Confirmation Before Writing

Show the full ADR and ask:

```
ADR-003: Use PostgreSQL Instead of Redis for Circuit Breaker State
──────────────────────────────────────────────────────────────────
[full ADR content]

Write to docs/adr/MYYES-17097-ADR-003-use-postgresql-circuit-breaker.md? (yes / edit / cancel)
```

- **yes** — write the file
- **edit** — show each section and let the user modify, then ask again
- **cancel** — exit without writing

---

## Commit Offer

**This step is mandatory — never skip it.** After writing the ADR file, always print:

```
ADR-003 written: docs/adr/MYYES-17097-ADR-003-use-postgresql-circuit-breaker.md

Commit now? (yes / no)
```

If **yes**: stage the file and commit with:
```
docs(adr): ADR-003 use PostgreSQL instead of Redis for circuit breaker state
```

If **no**: remind the user to commit manually before switching branches.

---

## Superseding an Existing ADR

If the user says "this supersedes ADR-002" (or the skill infers it from context):

1. Update the existing ADR's `## Status` to:
   ```
   Superseded by [ADR-NNN](<TICKET>-ADR-NNN-<slug>.md)
   ```
2. Add to the new ADR's `## Status`:
   ```
   Accepted — supersedes [ADR-002](<TICKET>-ADR-002-<slug>.md)
   ```

Never delete or rewrite the old ADR — only update its Status line.

---

## Integration with Open Question resolution

When a workflow resolves Open Questions mid-implementation and marks a
`- [ ]` item as `- [x]`, it should check whether the resolution carries
architectural weight (a technology choice, a compliance constraint, a pattern
decision). If so, it prints:

```
⚑  "Consent timeout: 30 minutes confirmed with Legal" looks like an architectural
   decision worth preserving. Run /doc-adr open-questions to capture it.
```

This is a suggestion only — it never blocks the update flow.

---

## Independence from the SDD Pipeline

This skill has no dependency on `.specwork/` artifacts beyond the optional
Open Questions mode. It does not affect `/f-help`, `/f-status`, or any other
pipeline skill. It can be run at any point: before implementation, during, or
after merging.
