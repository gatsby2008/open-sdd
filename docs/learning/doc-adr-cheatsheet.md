# Doc / ADR Registry — Onboarding & Command Reference

The full cycle: **capture → store in the central registry → query in natural language**.
Every create command stores straight into the registry; there is no separate
publish step.

Four registries, one mechanism:

| Registry | Create (`list` to inspect) | Query (`/doc-ask` filter) |
|---|---|---|
| `service-catalog/` — endpoints, integrations, config | `/doc-catalog` | `type:catalog` |
| `adr-registry/<service>/` — decision history | `/doc-adr` | `type:adr` |
| `spec-registry/<service>/` — feature specs | `/doc-spec` (and `/f-mr` inside the pipeline) | `type:spec` |
| `investigation-registry/<service>/` — bug / exploration / improvement notes | `/doc-investigation` | `type:investigation` |

One query command, `/doc-ask`, reads all four; the filter is optional. When the
registry is the `raw/` half of a two-layer vault, `/doc-ingest` compiles it into the
`wiki/` layer (see [Ingesting: /doc-ingest](#ingesting-doc-ingest)).

> **Central registry** (`$OPEN_SDD_DOC_HOME`, default `${OPEN_SDD_ROOT:-~}/.opensdd/registry/`).
> Set `OPEN_SDD_DOC_HOME` to a team-shared Git repo for cross-service queries.

---

## Quick Start

```bash
# 1. Scan the current project and store its catalog in the registry
/doc-catalog
/doc-catalog --with-docs    # also store docs/architecture/, docs/product/, … as extra docs

# 2. Ask across every registry, from any project
/doc-ask "what services depend on consent-service?"

# 3. Record decisions and query them
/doc-adr "we chose PostgreSQL for circuit breaker state"
/doc-ask "why did consent-service pick PostgreSQL?"

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
- **`/doc-catalog list`** shows this service's catalog, its extra-doc count and its
  freshness: commits and code files changed since the `Verified at` commit recorded
  in the catalog header. `/doc-ask` shows that commit too, and warns when a loaded
  catalog was regenerated more than 90 days ago (`OPEN_SDD_CATALOG_MAX_AGE_DAYS`).

**When to run:** after adding an endpoint, changing integrations, or when the catalog is stale.

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

---

## Specs and investigations

### /doc-spec

Stores a feature spec in `spec-registry/<service>/<slug>-spec.md` — for hand-written or
standalone specs; inside the pipeline `/f-mr` does it automatically.
`/doc-spec <path>` stores that file; with no argument it uses the active `.specwork/`
spec; `/doc-spec list` shows the service's specs. Query with `/doc-ask`.

### /doc-investigation

Captures the current session's investigation as a structured document in
`investigation-registry/<service>/`, typed **bug**, **explore** or **improvements**:
`/doc-investigation [title] [bug|explore|improvements]`; `list` shows the service's
notes. Query with `/doc-ask`.

---

## Asking: /doc-ask

`/doc-ask <question> [type:catalog|adr|spec|investigation] [service:<name>]`

One query over the four registries (logic in `engine/registry.py`). It prints:

1. **INDEX** — one line per document (path, title, date). Always there: when term
   search misses (synonyms, a Spanish question over English docs) the model picks
   by title and reads.
2. **LOADED** — the best-matching documents, ranked by the question's terms
   (identifiers such as `LeadCreated` or `/api/v1/consent` weigh most), up to a
   budget (`OPEN_SDD_ASK_BUDGET`, default 60 000 characters). Large docs are
   trimmed to their matching `##` sections. If everything fits, everything loads.
3. **ALSO MATCHED** — the other matches by path, for the model to read on demand.
4. **HINTS** — how to read each registry (event chains, supersedes, Open Questions,
   investigations oldest first).

**Filters are optional.** `type:` narrows to one registry; `service:` to one service.
A service *named* in the question only boosts its documents — "who consumes X from
leads-service?" still needs the other services' catalogs. "Which specs have open
questions?" lists only the unresolved `- [ ]` items.

**Example questions:**
- "Who consumes ApplicationStageChangeEvent?"
- "Who calls /api/v1/consent?"
- "Why did we migrate to aws sdk v2?" (ADRs and specs in one answer)
- "type:spec which specs have open questions?"
- "type:investigation have we seen ReportToken reuse before?"

---

## Ingesting: /doc-ingest

`/doc-ingest [<path under raw/> | session]` — the *producer* half of the two-layer
(Karpathy) model. The `doc-*` commands write `raw/`; `/doc-ingest` compiles that
material into the interconnected `wiki/` layer that `/doc-ask` follows:

```
raw/  (source of truth, append-only)     wiki/  (compiled, interconnected)
  service-catalog/   ── /doc-ingest ──►  entities/  concepts/  sources/
  adr-registry/                          with [[backlinks]], kept indexes,
  spec-registry/                         and log.md (the ingest watermark)
  investigation-registry/
```

It only runs where the registry root is the `raw/` half of a two-layer vault —
i.e. there is a `wiki/` sibling of `raw/`. On a plain registry it says so and stops;
`/doc-ask` keeps working on `raw/` alone.

| Invocation | What it compiles |
|---|---|
| `/doc-ingest` | Everything in `raw/` modified after the newest `## [YYYY-MM-DD]` entry of `wiki/log.md` |
| `/doc-ingest service-catalog/leads-service.md` | That one source (any path under `raw/`) |
| `/doc-ingest session` | The current conversation — distill what it established into the wiki |
| `/doc-ingest list` | Facts only: vault layout, schema, last ingest, un-ingested docs. Writes nothing |

The command prints the vault layout (`raw/`, `wiki/`, schema file), the watermark, the
sources selected, and the compile protocol; the model then reads the vault schema
(`CLAUDE.md`/`AGENTS.md` at the vault root, authoritative when present), creates or
updates pages **in place** (grep first — never duplicate), writes in its own words with
`[[wikilinks]]` and a `## Source` section, updates the indexes, appends the `wiki/log.md`
entry, and verifies 0 broken links. `raw/` is never edited.

`/doc-ask` prints `WIKI: <path> (last ingest: <date>)` and warns when raw docs changed
after that date — running `/doc-ingest` clears the warning.

---

## Environment

| Variable | Effect |
|----------|--------|
| `$OPEN_SDD_DOC_HOME` | Root of the shared registry (e.g. `~/team/docs-registry`). Default: `${OPEN_SDD_ROOT:-$HOME}/.opensdd/registry/` |
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

On a two-layer vault the registry root above **is** `raw/`, with a `wiki/` sibling
(`wiki.md`, `log.md`, `entities/`, `concepts/`, `sources/`) that `/doc-ingest` compiles
into and `/doc-ask` reads.

---

## Recommended workflow

```bash
# First use in a project
/doc-catalog --with-docs                      # catalog + extra docs into the registry
/doc-adr "initial service architecture"       # foundational ADR

# Daily use
/doc-adr "decision of the day"                # record decisions as they happen
/doc-investigation "why X breaks" bug         # keep what an investigation found

# Two-layer vault only: compile raw/ into wiki/
/doc-ingest list                              # what is un-ingested (writes nothing)
/doc-ingest                                   # compile whatever changed since the last log entry

# Cross-service queries
/doc-ask "which services use SQS?"
/doc-ask "why did we decide X?"
/doc-ask "which specs touch LeadProcessor?"
```

---

**See also:**
- [open-sdd-architecture.md](open-sdd-architecture.md) — architectural overview
- [sdd-pipeline-cheatsheet.md](sdd-pipeline-cheatsheet.md) — pipeline command lookup
- [sdd-key-concepts.md](sdd-key-concepts.md) — cross-cutting concepts
- [VIBE-CODING.md](vibe-coding.md) — standalone commands without pipeline
