# provisioning-prc-api

Process API for Neon One's **Salesforce → Jira tickets** (Scenario 1 provisioning: one System Setup ticket per Closed Won Opportunity; Scenario 2 cancellation: one deactivation ticket per product line of a churned Opportunity) and **Jira → Salesforce status feedback**.
Part of the API-led trio: `salesforce-sys-api` (8081) · `jira-sys-api` (8082) · **`provisioning-prc-api` (8083)** — local ports; on CloudHub 2.0 every app listens on 8081 and reaches the system APIs on 443.

Owns the business rules: idempotency, ticket content (config-driven mapping), registry write-back, terminal vs transient
error handling with retry, inbound status events and the reconciliation sweep. Talks **only** to the two system APIs.

## Endpoints (`/api/v1`, spec in `src/main/resources/api/provisioning-prc-api.raml`)
| Method | Path | Purpose |
|---|---|---|
| GET | `/ping` | Liveness |
| POST | `/provisioning-requests` | One `ProvisioningRequested` (from salesforce-sys-api), routed on the registry row's request type (PROVISIONING → `provision-ticket`, DEACTIVATION → `deactivate-ticket`) → outcome `CREATED` / `LINKED_EXISTING_TICKET` / `SKIPPED_*` / `IGNORED_*` / `TERMINAL_ERROR` / `RETRY_SCHEDULED` / `RETRIES_EXHAUSTED` |
| POST | `/issue-status-events` | One `IssueStatusChanged` (from jira-sys-api webhook) → registry row updated by ticket key |
| POST | `/sweeps/instance-ready` | Run the reconciliation sweep now (also scheduled hourly) |
| GET | `/retry-queue` | Requests parked after transient failures (operations view) |

Schedulers: `retry-scheduler` (re-drives parked requests with exponential backoff) and `sweep-scheduler` (hourly reconciliation).

## The ticket mapping is configuration
`src/main/resources/mapping/provisioning-ticket.yaml` (System Setup) and `mapping/deactivation-ticket.yaml` (deactivation) decide what goes on the ticket (ADR-014, ADR-017, ADR-020). Each leaf is
`{ source | template | rule | value }` with optional `default` / `maxLength`; the YAML shape is the canonical
`IssueCreateRequest` of jira-sys-api. Named rules (`modules`, `webTemplateCopy`) live in `modules/TicketMapping.dwl`; the mapping currently uses the `modules` rule and a **static** `webTemplateCopy: NOT_PURCHASED` (the rule is wired but unused until Q21 is answered).
Adding a ticket field = editing the YAML. No flow changes.

## Outcome of a provisioning request
```
Requested registry row ─► Opportunity read ─► ticket built ─► Jira create ─► registry Created (+key, status)
                                                                    │
            terminal (400/401/403/404, APP:*, mapping bug) ─► registry Failed - Terminal (category Terminal/Mapping/Auth)
            transient (429/5xx/timeout/connectivity) ─► registry Retrying + retry_store (backoff) ─► … ─► Failed - Terminal (Transient) after maxAttempts
```
Salesforce Flows on the registry row do everything on the Opportunity/Account; Mule writes only the registry (ADR-013).

## Scenario 2 — deactivation (`deactivate-ticket`, ADR-020)
```
DEACTIVATION row (Product_Line__c) ─► Opportunity read ─► resolve-product-line (config deactivation.lines.<CODE>)
   A. line configured?  (project ≠ TBD)          else Failed - Terminal (Mapping) "No Jira target configured … re-drive once the project exists"
   B. Account has the line's instance id?         else Failed - Terminal (Mapping) "No CRM Instance on Account …"
   C. Opportunity already has <line>_Cancellation_JIRA__c?  → Cancelled, SKIPPED_EXISTING_KEY
   D. Jira already has a ticket labelled sf-deact-<opp>-<line> (not Done)?  → link it, LINKED_EXISTING_TICKET
   else build from mapping/deactivation-ticket.yaml ─► Jira create ─► registry Created
```
Per-line Jira target, instance field and labels are configuration (`deactivation.lines.NEON_CRM|NEON_FUNDRAISE|ARTS_PEOPLE`); Dev/UAT route every line to NSSU / System Setup as a stand-in, Prod routes Neon CRM to WORK / Deactivate Instance and leaves FUND/ARTS as `TBD` until Neon One creates them.

## Configuration
- `config-<env>.yaml`: Jira project per environment, `provisioning.requestTypes`, retry policy, sweep schedule, status-category map, `jira.issueTypeNames`, `deactivation.*` (mapping file, duplicate check, label prefix, missing-date text, per-line targets), system API hosts (UAT/Prod hold `REPLACE_ME` placeholders; on CloudHub the hosts are passed as deployment properties).
- `secure-<env>.yaml`: `api.clientSecret` (interim inter-app shared secret; must match the two system APIs; checked by `authorize-caller` when `api.enforceClientSecret=true`). Only `secure-dev.yaml` exists so far.

## Run locally
```bash
mvn clean package -DskipTests
# VS Code: Run → Start Debugging with -M-Dmule.env=dev -M-Dsecure.key=<key>; start the two system APIs too
curl -s http://localhost:8083/api/v1/ping
curl -s -X POST http://localhost:8083/api/v1/sweeps/instance-ready
curl -s http://localhost:8083/api/v1/retry-queue
```

## Deploy to CloudHub 2.0 (Maven route; the first deployment is manual — KB plan 16 §3)
```bash
mvn clean deploy -DmuleDeploy -Pdev -Dsecure.key="$MULE_SECURE_KEY" -Dcloudhub.sysSf.host=<host> -Dcloudhub.sysJira.host=<host>
# Credentials (anypoint.client.id / anypoint.client.secret) come from ~/.m2/settings.xml — connected app bluvium-neon-jira-deploy-sandbox.
# -Pdev deploys into the Anypoint environment Sandbox, private space Bluvium, replica size mule.nano, public endpoint on.
```

## Test
```bash
mvn clean test        # MUnit (16 tests): both system APIs mocked; Scenario 2: created / missing instance id / existing key / linked by label / unconfigured line. Not covered yet: retry re-drive from retry_store, RETRIES_EXHAUSTED, authorize-caller
```

Project knowledge base: `~/Desktop/NEONONE-KB`.
