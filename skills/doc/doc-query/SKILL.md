---
name: doc-query
description: Answer cross-service architecture questions by reading all service catalogs from the registry (default ~/.claude/service-catalog/, override with $CLAUDE_DOC_HOME). Ask things like "who consumes the LeadCreated SNS event?", "what services call /api/v1/consent?", "which services does marketing-service depend on?"
argument-hint: "free-text architecture question"
allowed-tools: Read, Bash(ls:*), Bash(find:*)
---

# Architecture Query

**Load**: `view ~/.claude/skills/doc/doc-query/SKILL.md`

---

## Registry Path

All registry reads resolve through a single environment variable:

```bash
REGISTRY="${CLAUDE_DOC_HOME:-$HOME/.claude}/service-catalog"
```

- **Default** (no env var set): `~/.claude/service-catalog/` — identical to the original behavior.
- **Override**: `export CLAUDE_DOC_HOME=/path/to/registry-root` — e.g., a cloned GitLab repo for team-shared catalogs.

The same variable controls `/doc-publish`, `/adr-publish`, and `/adr-query`, so all doc registries move together.

---

## What It Does

| Step | Action |
|------|--------|
| 1 | Lists all catalogs in `~/.claude/service-catalog/` |
| 2 | Reads every catalog file |
| 3 | Answers `$ARGUMENTS` using the combined knowledge |
| 4 | Cites which service(s) the answer comes from |

---

## Step 1 — Check Registry

```bash
ls "${CLAUDE_DOC_HOME:-$HOME/.claude}/service-catalog"/*.md 2>/dev/null
```

If empty, abort:

```
No service catalogs found in ~/.claude/service-catalog/.

Run /doc-catalog in each service project, then /doc-publish to register it.
```

List available catalogs before answering:

```
Reading 4 service catalogs:
  leads-service.md
  marketing-service.md
  consent-service.md
  transunion-service.md
```

---

## Step 2 — Read All Catalogs

Read every `.md` file in `~/.claude/service-catalog/`. Build a combined
knowledge base of:

- REST endpoints (method, path, request/response DTOs)
- SNS topics published (topic name, message schema)
- SQS queues consumed (queue name, message schema)
- Feign clients (target service, methods called)
- External integrations (third-party APIs, SDKs)
- Scheduled jobs
- Key configuration

---

## Step 3 — Answer the Question

Use the combined catalog knowledge to answer `$ARGUMENTS`.

### Query types and how to answer them

**Event flow** — "who publishes/consumes X?"
- Search SNS `Publishes` sections for the topic name
- Search SQS `Consumes` sections for the queue name
- Show the full chain: publisher → topic/queue → consumer

**Endpoint discovery** — "what services expose X endpoint?"
- Search all `Endpoints` sections for the path or method

**Dependency mapping** — "what does X service depend on?"
- Read X's Feign clients + external integrations
- List target services + third-party APIs

**Impact analysis** — "what breaks if leads-service goes down?"
- Find all services with a Feign client pointing to leads-service
- Find all services consuming queues/topics that leads-service publishes to

**Data ownership** — "who owns the consent_flag field?"
- Search DTOs and request/response schemas across all catalogs

---

## Step 4 — Format the Answer

Always cite the source catalog for every claim:

```
Question: Who consumes the LeadCreated SNS event?

LeadCreated is published by:
  leads-service  →  SNS topic: lead-events  (schema: LeadCreatedEvent)

Consumed by:
  marketing-service  →  SQS queue: marketing-lead-events-queue
  consent-service    →  SQS queue: consent-lead-events-queue

Sources: leads-service.md, marketing-service.md, consent-service.md
```

If the answer cannot be determined from the available catalogs:

```
Could not find this information in the current registry.
The catalog for <service> may be missing or outdated — run /doc-publish in that project.
```

---

## Related Skills

- `doc-catalog` — generates the catalog for a single service
- `doc-publish` — pushes the current project's catalog to the registry
