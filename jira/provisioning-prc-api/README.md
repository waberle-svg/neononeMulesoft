# provisioning-prc-api

Process API for Neon One's **Salesforce → Jira provisioning** and **Jira → Salesforce status feedback**.
Part of the API-led trio: `salesforce-sys-api` (8081) · `jira-sys-api` (8082) · **`provisioning-prc-api` (8083)**.

Owns the business rules: idempotency, ticket content (config-driven mapping), registry write-back, terminal vs transient
error handling with retry, inbound status events and the reconciliation sweep. Talks **only** to the two system APIs.

## Endpoints (`/api/v1`, spec in `src/main/resources/api/provisioning-prc-api.raml`)
| Method | Path | Purpose |
|---|---|---|
| GET | `/ping` | Liveness |
| POST | `/provisioning-requests` | One `ProvisioningRequested` (from salesforce-sys-api) → outcome `CREATED` / `SKIPPED_*` / `IGNORED_*` / `TERMINAL_ERROR` / `RETRY_SCHEDULED` / `RETRIES_EXHAUSTED` |
| POST | `/issue-status-events` | One `IssueStatusChanged` (from jira-sys-api webhook) → registry row updated by ticket key |
| POST | `/sweeps/instance-ready` | Run the reconciliation sweep now (also scheduled hourly) |
| GET | `/retry-queue` | Requests parked after transient failures (operations view) |

Schedulers: `retry-scheduler` (re-drives parked requests with exponential backoff) and `sweep-scheduler` (hourly reconciliation).

## The ticket mapping is configuration
`src/main/resources/mapping/provisioning-ticket.yaml` decides what goes on the ticket (ADR-014, ADR-017). Each leaf is
`{ source | template | rule | value }` with optional `default` / `maxLength`; the YAML shape is the canonical
`IssueCreateRequest` of jira-sys-api. Named rules (`modules`, `webTemplateCopy`) live in `modules/TicketMapping.dwl`.
Adding a ticket field = editing the YAML. No flow changes.

## Outcome of a provisioning request
```
Requested registry row ─► Opportunity read ─► ticket built ─► Jira create ─► registry Created (+key, status)
                                                                    │
            terminal (400/403/404, mapping bug) ─► registry Failed - Terminal (category Terminal/Mapping/Auth)
            transient (429/5xx/timeout/connectivity) ─► registry Retrying + retry_store (backoff) ─► … ─► Failed - Terminal (Transient) after maxAttempts
```
Salesforce Flows on the registry row do everything on the Opportunity/Account; Mule writes only the registry (ADR-013).

## Configuration
- `config-<env>.yaml`: Jira project per environment, retry policy, sweep schedule, status-category map, system API hosts.
- `secure-<env>.yaml`: `api.clientSecret` (interim inter-app shared secret; must match the two system APIs).

## Run locally
```bash
mvn clean package -DskipTests
# VS Code: Run → Start Debugging with -M-Dmule.env=dev -M-Dsecure.key=<key>; start the two system APIs too
curl -s http://localhost:8083/api/v1/ping
curl -s -X POST http://localhost:8083/api/v1/sweeps/instance-ready
curl -s http://localhost:8083/api/v1/retry-queue
```

## Test
```bash
mvn clean test        # MUnit: both system APIs mocked, full orchestration covered
```

Project knowledge base: `~/Desktop/NEONONE-KB`.
