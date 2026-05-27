# Architecture Query

Answers cross-service architecture questions by reading every catalog under `${OPEN_SDD_ROOT:-~}/.opensdd/registry/service-catalog/` and synthesizing an answer from the combined knowledge. The registry is populated by `/doc-publish` runs from each service.

## Usage

```bash
/doc-query who consumes the LeadCreated SNS event?
/doc-query what services call /api/v1/consent?
/doc-query which services does marketing-service depend on?
```

Pass any free-text architecture question as the argument.

## Example queries

Group your queries by intent. Each category below maps to a query type the skill knows how to answer — adapt the templates to the service, event, or field name in your own registry.

### Event flow — who publishes or consumes a message?

```bash
/doc-query who publishes the LeadCreated SNS event?
/doc-query which services consume the marketing-lead-events queue?
/doc-query trace LeadCreated from publisher to every downstream consumer
/doc-query list every SNS topic published across the registry
```

### Endpoint discovery — which service owns this URL?

```bash
/doc-query which service exposes POST /api/v1/consent?
/doc-query list every endpoint under /api/v1/leads
/doc-query are there any duplicated endpoint paths across services?
/doc-query which services expose endpoints reachable from the consumer portal?
```

### Dependency mapping — what does a service rely on?

```bash
/doc-query which services does leads-service call via Feign?
/doc-query what external APIs does transunion-service integrate with?
/doc-query show the full dependency graph for consumer-portal
/doc-query which services depend on package-orchestrator?
```

### Impact analysis — what breaks if X is unavailable?

```bash
/doc-query what breaks if leads-service goes down?
/doc-query which services would be affected by an outage of transunion-service?
/doc-query if we change the LeadCreated schema, who must update their consumers?
/doc-query which services are single points of failure for the lead-to-package flow?
```

### Data ownership — where does a field live?

```bash
/doc-query which service owns the consent_flag field?
/doc-query which DTOs include phone_number?
/doc-query where is the consumer email validated?
/doc-query which catalogs reference the LeadCreatedEvent schema?
```

### Operational — scheduled jobs, configuration, integrations

```bash
/doc-query list every scheduled job across all services
/doc-query which services run nightly batch jobs?
/doc-query which third-party SDKs are used in the registry?
/doc-query summarize the SQS queue topology — who consumes what?
```

### Discovery — what's even in the registry?

```bash
/doc-query summarize each service in one paragraph
/doc-query which services publish to SNS and which only consume from SQS?
/doc-query give me the architectural surface area of the consent flow end-to-end
```

Every answer cites the catalogs it pulled from — if a fact is wrong, refresh that service's catalog with `/doc-catalog` and `/doc-publish`.

## What it does

1. Lists every file under `${OPEN_SDD_ROOT:-~}/.opensdd/registry/service-catalog/`.
2. Reads each catalog.
3. Synthesizes an evidence-based answer citing the services involved and the relevant catalog entries.

## Requirements

- At least one catalog must exist under `${OPEN_SDD_ROOT:-~}/.opensdd/registry/service-catalog/` (or `$OPEN_SDD_DOC_HOME/service-catalog/` if the env var is set). Populate it by running `/doc-catalog` followed by `/doc-publish` in each service repository.

## Registry location

Defaults to `${OPEN_SDD_ROOT:-~}/.opensdd/registry/service-catalog/`. Override with `OPEN_SDD_DOC_HOME` to point at a different folder (e.g., a cloned GitLab repo for team sharing) — the skill reads from `$OPEN_SDD_DOC_HOME/service-catalog/`. See the bundle README's *Team-shared registry* section for the full setup guide.

## Limitations

- Answers are only as fresh as the most recent `/doc-publish` run per service. If a catalog reports stale information, re-run `/doc-catalog` and `/doc-publish` in the affected service.
- The skill never edits catalogs — it only reads them.

## Related Skills

- `/doc-catalog` — generates the per-service catalog.
- `/doc-publish` — publishes a catalog to the registry this skill reads.
