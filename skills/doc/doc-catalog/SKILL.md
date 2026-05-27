---
name: doc-catalog
description: Generate or update a service catalog document for the current microservice (Java Spring Boot or frontend). Scans the codebase to extract endpoints, integrations, dependencies, and key configuration. Writes docs/service-info.md. Use when starting a new service, after adding a new endpoint or integration, or when the catalog is out of date.
argument-hint: "optional: update — regenerate from scratch; or omit to generate/update"
allowed-tools: Read, Write, Bash(find src:*), Bash(find .:*), Bash(find app:*), Bash(find pages:*), Bash(grep -r:*), Bash(cat src/**/*.java), Bash(cat src/**/*.yml), Bash(cat src/**/*.yaml), Bash(cat src/**/*.properties), Bash(cat pom.xml), Bash(cat package.json), Bash(cat next.config.*), Bash(ls:*), Bash(mkdir:*)
---

# Service Catalog

**Load**: `view $OPEN_SDD_ROOT/skills/doc/doc-catalog/SKILL.md`

---

## Description

Scans the codebase and generates `docs/service-info.md` — a single-page catalog entry
for the current service documenting what it does, what it exposes, what it integrates
with, and how it is configured.

Supports two stacks:
- **Java Spring Boot** — REST endpoints, SQS/SNS, Feign clients, scheduled jobs
- **Frontend (React / Next.js / Vue)** — routes/pages, API calls, external SDKs, feature flags

The catalog is generated from the code, not written by hand. This keeps it accurate —
it reflects what is actually deployed, not what someone documented 6 months ago.

---

## Use Cases

- `/doc-catalog` — generate or update `docs/service-info.md` from the current codebase
- `/doc-catalog update` — force a full regeneration even if the file already exists

---

## Stack Detection

| Signal | Detected Stack |
|--------|---------------|
| `pom.xml` or `build.gradle` at repo root | Java Spring Boot |
| `package.json` at repo root (no `pom.xml`) | Frontend (React / Next.js / Vue) |
| Both present | Prefer Java; note the ambiguity in the catalog header |
| Neither found | Abort with: "Could not detect stack. Run from the project root." |

---

## What It Does — Java Spring Boot

| Step | Action |
|------|--------|
| 1 | Reads `pom.xml` or `build.gradle` → extracts `artifactId` as service name |
| 2 | Scans `application.yml` / `application.properties` for queue names, topic ARNs, and base URLs |
| 3 | Scans `@RestController` classes → extracts HTTP endpoints |
| 4 | Scans for `@SqsListener` annotations → extracts queues consumed |
| 5 | Scans for SNS publish calls → extracts topics published |
| 6 | Scans for `@FeignClient` interfaces → extracts service dependencies |
| 7 | Scans for `@Scheduled` → extracts background jobs |
| 8 | If `docs/service-info.md` exists → merges with existing content (see Merge Strategy) |
| 9 | Prints a preview and asks for confirmation |
| 10 | Writes `docs/service-info.md` |
| 11 | Offers to commit |

## What It Does — Frontend

| Step | Action |
|------|--------|
| 1 | Reads `package.json` → extracts `name` as service name and detects framework (Next.js, React, Vue) |
| 2 | Scans route/page definitions → extracts pages and routes |
| 3 | Scans API service files and `fetch`/`axios`/`useQuery` calls → extracts backend APIs consumed |
| 4 | Scans `package.json` dependencies → extracts meaningful external SDK integrations |
| 5 | Scans for feature flag usage → extracts flags and their purpose |
| 6 | Scans `.env.example`, `next.config.*`, `vite.config.*` → extracts key environment variables |
| 7 | If `docs/service-info.md` exists → merges with existing content (see Merge Strategy) |
| 8 | Prints a preview and asks for confirmation |
| 9 | Writes `docs/service-info.md` |
| 10 | Offers to commit |

---

## Scanning Rules — Java Spring Boot

### Service name
Read `<artifactId>` from `pom.xml`. If not found, use the root directory name.

### REST Endpoints
Scan all `@RestController` classes. For each `@RequestMapping`, `@GetMapping`,
`@PostMapping`, `@PutMapping`, `@DeleteMapping`, `@PatchMapping`:
- Extract HTTP method and path (resolve class-level + method-level mappings)
- Use Javadoc `@summary` or first sentence of the method Javadoc as description
- If no Javadoc, derive description from the method name (camelCase → words)
- Mark `[internal]` if path starts with `/internal/`

### SNS Publishing
Look for:
- `SnsTemplate.sendNotification(...)` / `SnsTemplate.convertAndSend(...)`
- `SnsClient.publish(...)`
- `AmazonSNS.publish(...)`
- Any class named `*EventPublisher`, `*SnsPublisher`, `*NotificationService` that wraps SNS

Extract the topic name or ARN from the call or from the `application.yml` property it references.

**Message schema**: identify the object being published (e.g., `snsTemplate.convertAndSend(topic, myEvent)`).
Locate the `myEvent` class and scan its fields:
- Extract field name, Java type, and description from Javadoc or field name (camelCase → words)
- Unwrap `Optional<T>` → show `T?`
- Skip transient, static, and framework-internal fields
- Mark as `[INFERRED]` when description is derived from field name rather than Javadoc

### SQS Consuming
Look for `@SqsListener("${property.name}")` or `@SqsListener("queue-name")`.
Resolve property placeholders against `application.yml`.

**Message schema**: inspect the method parameter annotated with `@SqsListener`:
```java
public void handle(MyMessage message) { ... }   // ← scan MyMessage
public void handle(@Payload MyMessage message)  // ← same
```
Locate the `MyMessage` class and scan its fields using the same rules as SNS above.
If the parameter is `String` or `Map`, note `raw payload — no typed schema`.

### Feign Clients
Look for `@FeignClient(name = "...", url = "...")`.
Extract the service name and base URL.

### Background Jobs
Look for `@Scheduled` or `@ScheduledJob` annotations.
Extract the method name and cron expression or fixed delay.

### DTOs (Request / Response)
For each `@RestController` method, extract:
- **Request DTO**: the parameter annotated with `@RequestBody` → locate its class
- **Response DTO**: the return type, unwrapping `ResponseEntity<T>` → `T`, `List<T>` → `T[]`

For each DTO class found, scan its fields:
- Extract field name, Java type, and description from Javadoc or field name (camelCase → words)
- Determine required vs optional: `@NotNull`, `@NotBlank`, `@NotEmpty` → required; `@Nullable`, `Optional<T>` → optional
- Unwrap `Optional<T>` → show `T?`
- Skip transient, static, and framework-internal fields
- Mark as `[INFERRED]` when description is derived from field name rather than Javadoc
- Deduplicate: if the same DTO appears in multiple endpoints, document it once and reference it by name

---

## Scanning Rules — Frontend

### Service name
Read `name` from `package.json`. Detect framework from dependencies:
- `next` → Next.js
- `react` (no `next`) → React
- `vue` → Vue

### Routes / Pages
Detect routing pattern from framework:

| Framework | Where to scan |
|-----------|--------------|
| Next.js (App Router) | `app/**/page.tsx`, `app/**/layout.tsx` |
| Next.js (Pages Router) | `pages/**/*.tsx` (exclude `_app`, `_document`, `api/`) |
| React Router | `<Route path="...">` and `createBrowserRouter(...)` in `src/` |
| Vue Router | `routes` array in `router/index.ts` or `router.ts` |

For each route: extract path, component name, and auth requirement (look for auth guards or middleware).

### API Calls (Backend services consumed)
Scan for:
- `fetch(...)` / `axios.*` calls with URL strings or env var references
- React Query / TanStack Query `useQuery`, `useMutation` with endpoint keys
- Custom API service files (`*Api.ts`, `*Service.ts`, `*Client.ts`) with HTTP calls

Extract: HTTP method, endpoint path, purpose (from function/variable name or JSDoc).

### External SDK Integrations
Scan `package.json` `dependencies` for known external integrations and report those present:

| Package | Integration |
|---------|------------|
| `@aws-amplify/*` | AWS Amplify (Auth, Storage, etc.) |
| `@auth0/*` | Auth0 authentication |
| `@stripe/*` | Stripe payments |
| `firebase` / `@firebase/*` | Firebase |
| `@datadog/*` | Datadog monitoring |
| `launchdarkly-*` / `@growthbook/*` | Feature flags |
| `@segment/*` | Analytics |
| `@sentry/*` | Error tracking |

Report only packages that are actually in `package.json`. Do not invent integrations.

### Feature Flags
Look for:
- `process.env.NEXT_PUBLIC_FEATURE_*` or `import.meta.env.VITE_FEATURE_*`
- LaunchDarkly `useFlags()` / `useLDClient()` calls
- GrowthBook `useFeature(...)` calls
- Any boolean env var prefixed with `FEATURE_`, `FF_`, or `ENABLE_`

Extract: flag name, purpose (from usage context).

### Environment Variables
Scan `.env.example`, `next.config.js/ts`, `vite.config.ts` for `NEXT_PUBLIC_*`, `VITE_*`, or other app-level env vars. Exclude secrets (anything with `SECRET`, `KEY`, `TOKEN`, `PASSWORD`).

---

## Output Format — Java Spring Boot

```markdown
# Service: <artifactId>

> Last updated: <date> · Generated by /doc-catalog · Stack: Java Spring Boot

## Overview
<One paragraph describing what the service does — inferred from controller names,
service class names, and application.yml context. Mark inferences as [INFERRED].>

## Endpoints

| Method | Path | Request | Response | Auth |
|--------|------|---------|----------|------|
| POST | /api/v1/consent | `ConsentRequest` | `ConsentResponse` | Cognito JWT |
| GET | /api/v1/leads/:id | — | `LeadDTO` | Cognito JWT |
| GET | /internal/tlo/circuit/status | — | `CircuitStatusDTO` | [internal] |

Auth column: `Cognito JWT` if secured, `public` if not, `[INFERRED]` if unclear.
Request/Response columns show the DTO name — full schema in the **Data Types** section below.

## Publishes (SNS)

| Topic | Event type | Trigger |
|-------|-----------|---------|
| `credit-results-topic` | `CreditReportReady` | TLO returns a result |
| `credit-results-topic` | `CreditReportFailed` | TLO circuit is open |

Topic ARN: `${aws.sns.credit-results-topic-arn}`

### `CreditReportReady` schema
| Field | Type | Description |
|-------|------|-------------|
| `leadId` | `String` | Lead identifier |
| `score` | `Integer` | Credit score (300–850) |
| `reportDate` | `LocalDate` | Date of the credit report |
| `provider` | `CreditProvider` | Credit bureau used [INFERRED] |

### `CreditReportFailed` schema
| Field | Type | Description |
|-------|------|-------------|
| `leadId` | `String` | Lead identifier |
| `reason` | `FailureReason` | CIRCUIT_OPEN or TIMEOUT |

Omit schema subsections when the published type is `String` or `Map` (raw payload).

## Consumes (SQS)

| Queue | Source topic | Event type | Published by |
|-------|-------------|-----------|-------------|
| `transunion-requests-queue` | `credit-requests-topic` | `CreditCheckRequested` | leads-service [INFERRED] |

### `CreditCheckRequested` schema
| Field | Type | Description |
|-------|------|-------------|
| `leadId` | `String` | Lead identifier |
| `checkType` | `CreditCheckType` | SOFT or HARD |
| `requestedAt` | `Instant` | When the check was requested |

Omit schema subsections when the listener parameter is `String` or `Map` (raw payload).

## Calls (Feign)

| Service | Base URL property | Purpose |
|---------|------------------|---------|
| leads-service | `${feign.leads-service.url}` | Fetch lead data |

## Background Jobs

| Job | Schedule | Purpose |
|-----|----------|---------|
| `cleanupExpiredConsents` | `0 0 * * * *` | Remove expired records |

Omit this section if no scheduled jobs are found.

## Data Types (DTOs)

### `ConsentRequest`
Used by: `POST /api/v1/consent` (request body)

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `leadId` | `String` | ✓ | Lead identifier |
| `consentType` | `ConsentType` | ✓ | Type of consent granted |
| `source` | `String` | ✗ | Channel where consent was obtained [INFERRED] |

### `ConsentResponse`
Used by: `POST /api/v1/consent` (response)

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | `UUID` | ✓ | Consent record identifier |
| `leadId` | `String` | ✓ | Lead identifier |
| `createdAt` | `Instant` | ✓ | When the consent was recorded |

Omit this section if no typed request/response DTOs are found.

## Key Configuration

| Property | Purpose |
|----------|---------|
| `aws.sqs.transunion-requests-queue` | Inbound request queue name |
| `aws.sns.credit-results-topic-arn` | Outbound results topic ARN |
```

---

## Output Format — Frontend

```markdown
# Service: <package-name>

> Last updated: <date> · Generated by /doc-catalog · Stack: <framework>

## Overview
<One paragraph describing what the application does — inferred from page names,
route structure, and API calls. Mark inferences as [INFERRED].>

## Pages / Routes

| Path | Component | Purpose | Auth |
|------|-----------|---------|------|
| / | HomePage | Landing page | public |
| /consent | ConsentPage | Consent capture form | Cognito JWT |
| /dashboard | DashboardPage | User dashboard | Cognito JWT |

Auth column: guard/middleware name if found, `public` if no auth, `[INFERRED]` if unclear.

## Backend APIs Consumed

| Method | Endpoint | Purpose |
|--------|----------|---------|
| POST | /api/v1/consent | Submit consent record |
| GET | /api/v1/leads/:id | Fetch lead data |

## External Integrations

| Integration | Package | Purpose |
|-------------|---------|---------|
| AWS Amplify Auth | `@aws-amplify/auth` | Cognito authentication |
| Sentry | `@sentry/react` | Error tracking |

Omit this section if no known external SDKs are found.

## Feature Flags

| Flag | Purpose |
|------|---------|
| `NEXT_PUBLIC_FEATURE_CONSENT_UI` | Toggle consent form visibility |

Omit this section if no feature flags are found.

## Key Configuration

| Variable | Purpose |
|----------|---------|
| `NEXT_PUBLIC_API_BASE_URL` | Base URL for backend API calls |
| `NEXT_PUBLIC_COGNITO_USER_POOL_ID` | Cognito user pool |
```

---

## Merge Strategy

If `docs/service-info.md` already exists:

1. Parse its existing sections
2. For each section: if the scanned code produces a different result, show a diff
3. Preserve any manually written content marked with `<!-- manual -->` — never overwrite it
4. Ask before replacing any manually written content

```
Existing docs/service-info.md found. Changes detected:

  Endpoints:  +1 new  (POST /internal/tlo/circuit/reset — not in current doc)
  Publishes:  no change
  Consumes:   no change

Update the file with these changes? (yes / no / diff)
```

---

## Confirmation Before Writing

Show a summary and ask:

```
docs/service-info.md ready for <service-name>:
  [Java]     3 endpoints · 2 SNS topics · 1 SQS queue · 2 Feign clients
  [Frontend] 5 routes · 3 API endpoints · 2 external integrations · 1 feature flag

Write to docs/service-info.md? (yes / edit / cancel)
```

- **yes** — write the file
- **edit** — show each section, let the user modify, ask again
- **cancel** — exit without writing

---

## Commit Offer

**This step is mandatory — never skip it.** After writing:

```
docs/service-info.md written.

Commit now? (yes / no)
```

If **yes**: commit with:
```
docs(catalog): add/update service catalog for <service-name>
```

---

## Independence from the SDD Pipeline

This skill has no dependency on `.specwork/` artifacts and does not affect
`/f-help`, `/f-status`, or any other SDD pipeline skill. It can be run at any
point — on an existing service, after a new endpoint or page is added, or as
part of onboarding a service to the catalog.

---

## Related Skills

- `doc-adr` — capture architectural decisions made while building or evolving the service
