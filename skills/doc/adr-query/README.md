# ADR Query

Answers architecture-decision questions by reading every ADR under `~/.claude/adr-registry/*/` and synthesizing an answer from the combined knowledge. The registry is populated by `/adr-publish` runs from each service.

## Usage

```bash
/adr-query why did consumer-portal pick PostgreSQL for circuit-breaker state?
/adr-query which services have superseded ADRs?
/adr-query show every ADR that references Cognito
```

Pass any free-text decision question as the argument.

## Example queries

Group your queries by intent. Each category below maps to a query type the skill knows how to answer — adapt the templates to the service, technology, or pattern in your own registry.

### Decision lookup — why did we pick X over Y?

```bash
/adr-query why did consumer-portal pick PostgreSQL for circuit-breaker state?
/adr-query why did leads-service adopt shlink for URL shortening?
/adr-query which ADRs explain why we chose Feign over WebClient?
```

### Topic scan — which ADRs touch a technology or concept?

```bash
/adr-query show me every ADR about retries
/adr-query which ADRs reference Cognito?
/adr-query find decisions involving SQS dead-letter queues
/adr-query which ADRs mention PII handling?
```

### Status filter — which decisions are still active?

```bash
/adr-query which ADRs have been superseded?
/adr-query list every deprecated decision and its replacement
/adr-query show the supersedes chain for circuit-breaker decisions
```

### Cross-service patterns — do multiple services agree?

```bash
/adr-query do multiple services persist state in Postgres?
/adr-query which services have adopted optimistic locking?
/adr-query are retry policies consistent across the registry?
```

### Consequence search — which decisions traded off X?

```bash
/adr-query which decisions added a DB read on the hot path?
/adr-query which ADRs accepted increased latency in exchange for durability?
/adr-query find decisions that expanded our ops footprint
```

### Discovery — what's in the registry?

```bash
/adr-query summarize the architectural decisions per service
/adr-query list every ADR title across the registry
/adr-query which Jira tickets are referenced in ADRs?
```

Every answer cites the source as `<service>/<ADR-file>` — if a fact is stale, refresh that service's ADRs with `/adr-publish`.

## What it does

1. Lists every service subdir under `~/.claude/adr-registry/`.
2. **Detects whether the question targets a specific service** — looks for kebab-case tokens in the query (e.g., `transunion-service`, `consumer-portal`) and matches them against the registry's subdir names. When a match is found, narrows the read scope to that subdir; otherwise reads the full registry. Aggregate questions ("which services…", "compare", "across services") always trigger a full read.
3. Reads the ADRs in scope.
4. Synthesizes an evidence-based answer, citing each claim with `<service>/<ADR-file>`.

### Scoping examples

| Query | Scope |
|-------|-------|
| `/adr-query why are we not using Redis in transunion-service?` | `transunion-service/` only |
| `/adr-query show every ADR about retries` | All services (topic scan, no service name) |
| `/adr-query do multiple services persist state in Postgres?` | All services (aggregate keyword) |
| `/adr-query compare consumer-portal and transunion-service on locking` | Both subdirs (multi-match, no aggregate) |

The narrowing keeps responses faster and avoids spending tokens on unrelated ADRs.

## Requirements

- At least one ADR must exist under `~/.claude/adr-registry/*/` (or `$CLAUDE_DOC_HOME/adr-registry/*/` if the env var is set). Populate it by running `/doc-adr` followed by `/adr-publish` in each service repository.

## Registry location

Defaults to `~/.claude/adr-registry/`. Override with `CLAUDE_DOC_HOME` to point at a different folder (e.g., a cloned GitLab repo for team sharing) — the skill reads from `$CLAUDE_DOC_HOME/adr-registry/`. See the bundle README's *Team-shared registry* section for the full setup guide.

## Limitations

- Answers are only as fresh as the most recent `/adr-publish` run per service. If an answer references a stale decision, re-run `/adr-publish` in the affected project.
- The skill never edits ADRs — it only reads them.

## Related Skills

- `/doc-adr` — creates an ADR under `docs/adr/`.
- `/adr-publish` — publishes ADRs to the registry this skill reads.
- `/doc-query` — same publish/query pattern, but for service catalogs.
