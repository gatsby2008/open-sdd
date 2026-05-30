# Doc / ADR Registry — Onboarding & Command Reference

The full cycle: **extract structure → publish to central registry → query in natural language**.

Two registries, one mechanism:
- **Service Catalog** (`service-catalog/`) — architecture, specs, security
- **ADR Registry** (`adr-registry/`) — decision history

> **Central registry** (`$OPEN_SDD_DOC_HOME`, default `${OPEN_SDD_ROOT:-~}/.opensdd/registry/`).
> Set `OPEN_SDD_DOC_HOME` to a team-shared Git repo for cross-service queries.

---

## Quick Start

```bash
# 1. Scan the current project — generates findings for docs/service-info.md
/doc-catalog

# 2. Publish the catalog to the central registry
/doc-publish --with-docs   # also publishes docs/architecture/, docs/product/, docs/security/

# 3. Query published docs from any project
/doc-query "what services depend on consent-service?"

# 4. Create ADRs for important decisions
/doc-adr "we chose PostgreSQL for circuit breaker state"
/adr-publish
/adr-query "why did consent-service pick PostgreSQL?"

# 5. Detect drift between docs and code
/doc-freshness
```

---

## Service Catalog

### /doc-catalog

Scans the current project and produces structured findings (endpoints, SQS listeners, Feign clients, DTOs, config). Does not write anything — the LLM uses the output to generate/update `docs/service-info.md`.

```
$ /doc-catalog
Stack: java
Service: leads-service

=== ENDPOINTS ===
POST /api/v1/leads            leads.api.LeadController
POST /api/v1/leads/offer      leads.api.LeadController

=== SQS LISTENERS ===
LeadOrchestrationConsumer.processLead(..)

=== FEIGN CLIENTS ===
ConsentServiceClient (consent-service)
MyYesGoClient (myyesgo-api)
```

**When to run:** after adding an endpoint, changing integrations, or when the catalog is stale.

### /doc-publish

Publishes `docs/service-info.md` to the central registry.

```
$ /doc-publish
Published: docs/service-info.md -> $REGISTRY/leads-service.md

# With extra docs (architecture, product, security, features)
$ /doc-publish --with-docs
Published: docs/service-info.md -> $REGISTRY/leads-service.md
Published 12 extra docs to $REGISTRY/docs/leads-service/

# List what's registered
$ /doc-publish list
Registered in $REGISTRY/:
  consent-service.md        (last updated May 14 09:17)
  leads-service.md          (last updated May 30 12:00)

Extra docs published for:
  leads-service (12 extra docs)
```

**What `--with-docs` uploads:**
- `docs/architecture/*.md` — system-overview, domain-models, patterns-review
- `docs/features/*.md` — feature specs, sequences, decisions
- `docs/product/*.md` — product-spec, gap-analysis, feature-inventory
- `docs/security/*.md` — security-report, findings
- `docs/*.md` — any other top-level .md (index, contributing, etc.)

### /doc-query

Reads all documents from the registry and answers cross-service questions with source citation.

```
$ /doc-query "what services consume the LeadCreated event?"

Reading 18 documents:
  leads-service/system-overview.md
  leads-service/integration-architecture.md
  consent-service/architecture-overview.md
  ...

Answer: consent-service consumes LeadCreated via SQS
(leads-service/integration-architecture.md:142 — "Event flow" diagram)
```

**Example questions:**
- "Who calls /api/v1/consent?"
- "What services depend on transunion-service?"
- "Which services have SQS listeners?"
- "What's the tech stack of leads-service?"

---

## Product Specs

### /spec-query

Reads `product-spec.md`, `gap-analysis.md`, `feature-inventory.md` from the registry (or `docs/product/` locally as fallback).

```
$ /spec-query "what high gaps are still open in leads-service?"

Reading 3 product spec documents:
  leads-service/product-spec.md
  leads-service/gap-analysis.md
  leads-service/feature-inventory.md

Answer: 9 high gaps open — no automatic retry/circuit-breaker,
no role-based permissions, consent records missing updated_by...
(gap-analysis.md:77-170 — High Gaps section)
```

**Example questions:**
- "What user stories are still unmet?"
- "What's the status of US-20 (per-person authz)?"
- "How many critical gaps exist and why were they deferred?"
- "What features were added in V3.6 vs V3.7?"

---

## Security

### /sec-query

Reads `docs/security/*.md` and `gl-*-report*.json` from the registry (or local).

```
$ /sec-query "what CVEs are in accepted-risk?"

Reading 2 security documents:
  leads-service/security-report.md
  leads-service/gl-sast-report.json

Answer: 3 CVEs in accepted-risk — commons-compress 1.24.0
(test-scope via Testcontainers), snakeyaml 2.0...
(security-report.md:34-42 — Accepted Risks table)
```

**Example questions:**
- "What findings were closed by the bump to Boot 3.5.14?"
- "Are there any open production findings?"
- "How many SAST findings and how were they triaged?"

---

## ADRs (Architecture Decision Records)

### /doc-adr

Creates an ADR in `docs/adr/<ticket>-ADR-<NNN>-<kebab-slug>.md`.

```
$ /doc-adr "choose PostgreSQL for circuit breaker state"

Next ADR number: ADR-001
Branch: feature/leadsConsentOrchestration

No specs or decisions files found. Provide context directly.

---
Use this info to draft the ADR, confirm with the user,
then write the file to docs/adr/ and offer to commit.
```

**Modes:**
- **`/doc-adr <topic>`** — create ADR from scratch
- **`/doc-adr open-questions`** — pull context from OQs in `.specwork/` (pipeline) or `docs/decisions.md` / `docs/open-questions.md` (standalone)
- **No active pipeline:** falls back to `docs/decisions.md` or prompts for direct context

### /adr-publish

Publishes all ADRs from `docs/adr/` to the central registry.

```
$ /adr-publish
Published 3 ADRs to $REGISTRY/leads-service/

$ /adr-publish list
Registered:
  leads-service/  (3 ADRs)
  consent-service/ (1 ADR)
```

### /adr-query

Reads ADRs from the registry and answers decision questions.

```
$ /adr-query "why did leads-service pick PostgreSQL for circuit-breaker state?"

Available ADR services:
  leads-service/
  consent-service/

Target service: leads-service

==== leads-service/IR-62-ADR-001-postgres-circuit-breaker.md ====
...

Answer: PostgreSQL was chosen because the circuit-breaker state
needs to survive service restarts (leads-service/IR-62-ADR-001.md:12)
```

**Scope narrowing:** pass a service name as argument to scope the query. Matching uses substring matching against the directory name, so `leads` matches `leads-service`.

**Aggregate queries:** use "all services", "across", "compare", "which services" to read every ADR across the registry.

---

## Freshness

### /doc-freshness

Detects drift between docs and actual repo state.

```
$ /doc-freshness

=== doc-freshness ===
Repo: /Users/.../leads
Branch: feature/leadsConsentOrchestration
Last commit: 2026-05-27

--- Cross-reference validity ---
  [OK] All 16 links in index.md resolve

--- Orphan docs (not referenced in index.md) ---
  [DRIFT] Not listed in index.md: docs/CODING_STANDARDS.md
  [DRIFT] Not listed in index.md: docs/features/detailed-leads-orchestration/decisions.md

--- Version drift ---
  [OK] No version in index.md title — skipping version check

--- Doc staleness (last update) ---
  [DRIFT] product-spec.md claims 2026-04-22 — 35 days stale
  [DRIFT] system-overview.md claims 2026-04-22 — 35 days stale

--- Endpoint drift ---
  [DRIFT] Path in docs not found in code: /some/endpoint

--- Summary ---
Drift items found: 15
```

**What it detects:**
1. **Broken links** — references in index.md that don't resolve to real files
2. **Orphan docs** — `.md` files that exist but aren't listed in index.md
3. **Version** — mismatch between index.md title and build.gradle/pom.xml/package.json
4. **Staleness** — docs with `**Date:**` older than 30 days from last repo commit
5. **Endpoints** — paths documented in architecture/ that don't exist in Java code

---

## Environment

| Variable | Effect |
|----------|--------|
| `$OPEN_SDD_DOC_HOME` | Root of the shared registry (e.g. `~/team/docs-registry`). Default: `${OPEN_SDD_ROOT:-$HOME}/.opensdd/registry/` |
| `$OPEN_SDD_ROOT` | Absolute path to open-sdd (set if you installed the pipeline) |

Service name is extracted from `docs/service-info.md` (heading `# Service: name` or `# name`), or from the git root directory name.

---

## Registry structure

```
$OPEN_SDD_DOC_HOME/
├── service-catalog/
│   ├── consent-service.md
│   ├── leads-service.md
│   └── docs/                        # published with --with-docs
│       ├── consent-service/
│       │   ├── system-overview.md
│       │   └── security-report.md
│       └── leads-service/
│           ├── product-spec.md
│           ├── gap-analysis.md
│           └── patterns-review.md
└── adr-registry/
    ├── leads-service/
    │   ├── IR-62-ADR-001-postgres-circuit-breaker.md
    │   └── IR-62-ADR-002-transactional-outbox.md
    └── consent-service/
        └── ADR-001-choose-consent-storage.md
```

---

## Recommended workflow

```bash
# First use in a project
/doc-catalog                                  # scan the project
/doc-adr "initial service architecture"       # foundational ADR
/doc-publish --with-docs                      # publish everything to registry

# Daily use
/doc-freshness                                # check drift before changing docs
/doc-adr "decision of the day"                # record decisions
/adr-publish                                  # publish new ADRs

# Cross-service queries
/doc-query "which services use SQS?"
/spec-query "what high gaps in leads?"
/sec-query "are there open CVEs?"
/adr-query "why did we decide X?"
```

---

**See also:**
- [open-sdd-architecture.md](open-sdd-architecture.md) — architectural overview
- [sdd-pipeline-cheatsheet.md](sdd-pipeline-cheatsheet.md) — pipeline command lookup
- [sdd-key-concepts.md](sdd-key-concepts.md) — cross-cutting concepts
- [VIBE-CODING.md](vibe-coding.md) — standalone commands without pipeline
