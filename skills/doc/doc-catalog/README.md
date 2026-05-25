# Service Catalog

Scans the current service and generates `docs/service-info.md` — a
single-page catalog entry documenting what the service does, what it exposes,
what it publishes, what it consumes, and who it calls. Supports Java Spring Boot
and frontend (React / Next.js / Vue).

Generated from the code, not written by hand. Accurate by default.

---

## Usage

```bash
# Generate or update docs/service-info.md
/doc-catalog

# Force full regeneration
/doc-catalog update
```

---

## What It Produces

```markdown
# Service: transunion-service

## Overview
Queries TLO for credit and vehicle data on behalf of leads-service...

## Endpoints
| Method | Path | Description | Auth |
|--------|------|-------------|------|
| POST | /api/v1/tlo/search-person | ... | Cognito JWT |
| GET | /internal/tlo/circuit/status | ... | Cognito JWT |

## Publishes (SNS)
| Topic | Event type | Trigger |
|-------|-----------|---------|
| `credit-results-topic` | `CreditReportReady` | TLO returns a result |

## Consumes (SQS)
| Queue | Source topic | Event type | Published by |
|-------|-------------|-----------|-------------|
| `transunion-requests-queue` | `credit-requests-topic` | `CreditCheckRequested` | leads-service |

## Calls (Feign)
| Service | Base URL property | Purpose |
|---------|------------------|---------|
| leads-service | `${feign.leads-service.url}` | Fetch lead data |

## Key Configuration
| Property | Purpose |
|----------|---------|
| `aws.sqs.transunion-requests-queue` | Inbound request queue |
```

---

## Why this matters

In a microservices architecture, knowing who publishes and who consumes a given
SNS event is critical for debugging and impact analysis. Without a catalog, the
answer requires searching across every repo.

With `docs/service-info.md` in each repo, you can:
- Answer "who consumes `CreditCheckRequested`?" by searching across repos
- See the full dependency chain of a service at a glance
- Onboard new developers without a live walkthrough

---

## Independent of the SDD pipeline

This skill has no dependency on `.specwork/` artifacts. It can be run on any
existing Spring Boot service at any time.
