# Doc / ADR Registry — Onboarding & Command Reference

The full cycle: **capture → store in the central registry → query in natural language**.
Every create command stores straight into the registry; there is no separate
publish step.

Four registries, one mechanism:

| Registry | Create (`list` to inspect) | Query |
|---|---|---|
| `service-catalog/` — endpoints, integrations, config | `/doc-catalog` | `/doc-catalog-query` |
| `adr-registry/<service>/` — decision history | `/doc-adr` | `/doc-adr-query` |
| `spec-registry/<service>/` — feature specs | `/doc-spec` (and `/f-mr` inside the pipeline) | `/doc-spec-query` |
| `investigation-registry/<service>/` — bug / exploration / improvement notes | `/doc-investigation` | `/doc-investigation-query` |

Architecture design docs live apart, in the repo pointed to by `$OPEN_SDD_ARCH_HOME`;
query them with `/arch-query`.

> **Central registry** (`$OPEN_SDD_DOC_HOME`, default `${OPEN_SDD_ROOT:-~}/.opensdd/registry/`).
> Set `OPEN_SDD_DOC_HOME` to a team-shared Git repo for cross-service queries.

---

## Quick Start

```bash
# 1. Scan the current project and store its catalog in the registry
/doc-catalog
/doc-catalog --with-docs    # also store docs/architecture/, docs/product/, … as extra docs

# 2. Query catalogs from any project
/doc-catalog-query "what services depend on consent-service?"

# 3. Record decisions and query them
/doc-adr "we chose PostgreSQL for circuit breaker state"
/doc-adr-query "why did consent-service pick PostgreSQL?"

# 4. Store a hand-written spec, capture an investigation
/doc-spec docs/my-feature-spec.md
/doc-investigation "vehicle lookup cache bug" bug
```

---

## Service Catalog

### /doc-catalog

Scans the current project and prints structured findings (endpoints, SQS listeners,
SNS publishers, Feign clients, scheduled jobs, DTOs, config — or routes, API calls and
env vars for frontend projects). The LLM turns them into the catalog and writes it to
`$REGISTRY/service-catalog/<service>.md`.

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

- **`--with-docs`** also stores the repo's extra docs (`docs/architecture/`,
  `docs/features/`, `docs/product/`, `docs/security/`, other top-level `docs/*.md`)
  under `service-catalog/docs/<service>/`.
- **`/doc-catalog list`** shows this service's catalog and its extra-doc count.

**When to run:** after adding an endpoint, changing integrations, or when the catalog is stale.

### /doc-catalog-query

Reads every catalog and extra doc in `service-catalog/` and answers cross-service
questions, citing the source file.

**Example questions:**
- "Who calls /api/v1/consent?"
- "What services depend on transunion-service?"
- "Which services have SQS listeners?"
- "What's the tech stack of leads-service?"

---

## ADRs (Architecture Decision Records)

### /doc-adr

Drafts an ADR and stores it in the registry — there is no in-repo `docs/adr/`:
`$REGISTRY/adr-registry/<service>/<TICKET>-ADR-NNN-<kebab-slug>.md`
(`NOTICKET` when the branch has no ticket). The script prints the next number and
the existing ADRs; the LLM drafts, confirms with you, then writes.

**Modes:**
- **`/doc-adr <topic>`** — create an ADR from scratch
- **`/doc-adr open-questions`** — pull context from the resolved OQs in `.specwork/` (pipeline) or `docs/decisions.md` / `docs/open-questions.md` (standalone). `/f-mr` suggests it when the spec resolved OQs worth preserving
- **`/doc-adr list`** — ADRs already registered for this service

### /doc-adr-query

Reads ADRs from the registry and answers decision questions.

- **Scope narrowing:** pass a service name; it matches registry directories by
  substring, so `leads` matches `leads-service`.
- **Aggregate queries:** "all services", "across", "compare", "which services" read
  every ADR in the registry.

---

## Specs and investigations

### /doc-spec

Stores a feature spec in `spec-registry/<service>/<slug>-spec.md` — for hand-written or
standalone specs; inside the pipeline `/f-mr` does it automatically.
`/doc-spec <path>` stores that file; with no argument it uses the active `.specwork/`
spec; `/doc-spec list` shows the service's specs. Query with `/doc-spec-query`.

### /doc-investigation

Captures the current session's investigation as a structured document in
`investigation-registry/<service>/`, typed **bug**, **explore** or **improvements**:
`/doc-investigation [title] [bug|explore|improvements]`; `list` shows the service's
notes. Query with `/doc-investigation-query`.

---

## Environment

| Variable | Effect |
|----------|--------|
| `$OPEN_SDD_DOC_HOME` | Root of the shared registry (e.g. `~/team/docs-registry`). Default: `${OPEN_SDD_ROOT:-$HOME}/.opensdd/registry/` |
| `$OPEN_SDD_ARCH_HOME` | Architecture design docs repo read by `/arch-query` |
| `$OPEN_SDD_ROOT` | Absolute path to open-sdd (set if you installed the pipeline) |

**Service name** (`lib/service-name.sh`, first hit wins): `spring.application.name`
(`application.yml` / `.properties`) → first `# Heading` of `docs/service-info.md` →
git repo basename → `unknown`; always lowercase kebab-case.

---

## Registry structure

```
$OPEN_SDD_DOC_HOME/
├── service-catalog/
│   ├── consent-service.md
│   ├── leads-service.md
│   └── docs/                        # stored with --with-docs
│       └── leads-service/
│           ├── product-spec.md
│           └── patterns-review.md
├── adr-registry/
│   └── leads-service/
│       ├── IR-62-ADR-001-postgres-circuit-breaker.md
│       └── IR-62-ADR-002-transactional-outbox.md
├── spec-registry/
│   └── leads-service/
│       └── ir-62-spec.md
└── investigation-registry/
    └── leads-service/
        └── <date>-<slug>.md
```

---

## Recommended workflow

```bash
# First use in a project
/doc-catalog --with-docs                      # catalog + extra docs into the registry
/doc-adr "initial service architecture"       # foundational ADR

# Daily use
/doc-adr "decision of the day"                # record decisions as they happen
/doc-investigation "why X breaks" bug         # keep what an investigation found

# Cross-service queries
/doc-catalog-query "which services use SQS?"
/doc-adr-query "why did we decide X?"
/doc-spec-query "which specs touch LeadProcessor?"
```

---

**See also:**
- [open-sdd-architecture.md](open-sdd-architecture.md) — architectural overview
- [sdd-pipeline-cheatsheet.md](sdd-pipeline-cheatsheet.md) — pipeline command lookup
- [sdd-key-concepts.md](sdd-key-concepts.md) — cross-cutting concepts
- [VIBE-CODING.md](vibe-coding.md) — standalone commands without pipeline
