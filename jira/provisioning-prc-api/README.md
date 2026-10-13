# provisioning-prc-api

Process API for Neon One's **Salesforce → Jira tickets** (Scenario 1 provisioning: one System Setup ticket per Closed Won Opportunity; Scenario 2 cancellation: one deactivation ticket per product line of a churned Opportunity) and **Jira → Salesforce status feedback**.
Part of the API-led trio: `salesforce-sys-api` (8081) · `jira-sys-api` (8082) · **`provisioning-prc-api` (8083)** — local ports; on CloudHub 2.0 every app listens on 8081 and reaches the system APIs on 443.

Owns the business rules: idempotency, ticket content (config-driven mapping), registry write-back, terminal vs transient
error handling with retry, inbound status events and the reconciliation sweep. Talks **only** to the two system APIs.

## Endpoints (`/api/v1`, spec in `src/main/resources/api/provisioning-prc-api.raml`)
| Method | Path | Purpose |
|---|---|---|
| GET | `/ping` | Liveness |
| POST | `/provisioning-requests` | One `ProvisioningRequested` (from salesforce-sys-api), routed on the registry row's request type (SETUP → `provision-ticket`, DEACTIVATION → `deactivate-ticket`) → outcome `CREATED` / `LINKED_EXISTING_TICKET` / `SKIPPED_*` / `IGNORED_*` / `TERMINAL_ERROR` / `RETRY_SCHEDULED` / `RETRIES_EXHAUSTED` |
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

## Scenario 1 Order model
- A SETUP row **with `Order__c`** is processed per Order × product line (`provision-order-ticket`): Order Products of the line via salesforce-sys-api, ticket from `mapping/setup-order-ticket.yaml` (summary = Account name, Modules = flagged products, Implementation Type rule table, Account country/NTEE/technical contact, partner block when present, additional users, labels `sf-setup-<OrderId>-<line>`, reporter from `reporters.setup.*`). A row without `Order__c` keeps the Phase 1 Opportunity model (`provision-opportunity-ticket`).
- Guards: `APP:NO_SETUP_ITEMS` (no flagged Order Product on the line → Failed - Terminal, Mapping); an Order Product already keyed → Cancelled with that key; label search before creating (`provisioning.duplicateCheck`).
- **Created-issue store** (`created_issues_store`, persistent, 30 days): every key Jira returns is remembered before the registry patch; a retry links it from the store first (`LINKED_EXISTING_TICKET`, "recovered from the created-issue store") — independent of labels and of Salesforce. Applies to setup and deactivation tickets.
- Config: `provisioning.orderMappingFile`, `provisioning.duplicateCheck`, `provisioning.labelPrefix`; reporters in `reporters.*` (below).

## Request type rename
Salesforce renamed the `Request_Type__c` value PROVISIONING → **SETUP**. Mule accepts `SETUP` and `DEACTIVATION` only (`provisioning.requestTypes`); any other value, including the old PROVISIONING, ends as `IGNORED_TYPE` (INFO log, no ticket, the row stays Requested) until the publishing Flow is changed. `provisioning.legacyRequestTypes` is an emergency switch (spellings processed as SETUP with a WARN) and is empty in every environment by decision.

## Reporters
Jira reporters are configuration, by scenario and product line: `reporters.setup.lines.<LINE_CODE>` → `reporters.setup.default`, and `reporters.deactivation.lines.<LINE_CODE>` → `reporters.deactivation.default`; blank means Jira's default, the API account. Values are Atlassian account ids; any of them can be overridden as a Runtime Manager property with the same key. Dev: the API account for everything. UAT/Prod: Natalie Newendyke for CRM setup tickets, Chelsea Diehl for every deactivation ticket; Fundraise and Arts People setup reporters are blank until decided. Two Jira prerequisites per project: the Reporter field on the issue type's create screen (jira-sys-api drops the field where it is missing, e.g. live WORK / Deactivate Instance) and "Modify Reporter" for the API account.

## Modules on setup tickets
The ticket's Modules field is `Order.NeonCRM_Modules__c` exactly as the Salesforce Order Flow built it (from `Product2.Jira_Module_Value__c`), or the literal `NA` when that field is blank — a `source` + `default` leaf in `mapping/setup-order-ticket.yaml`, so the literal is a mapping-file change. Mule does not derive Modules from the Order Products any more (an earlier same-day version did). The Order is still read with `syncOnly=false` so the log can report "N flagged of M"; the ticket's group (duplicate label, existing-key guard, write-back) is the flagged items only. Implementation Type stays the rule table in the same YAML.
