# salesforce-sys-api

System API for **Neon One's Salesforce org**, part of the Salesforce ↔ Jira integration.
Part of the API-led trio: **`salesforce-sys-api` (8081)** · `jira-sys-api` (8082) · `provisioning-prc-api` (8083).

Owns: the JWT connection to Salesforce, the `Integration_Request__e` platform-event subscription (with replay),
reads of Opportunities, and **every write to `Integration_Transaction__c`** (the registry — the only object Mule writes).
Knows nothing about: Jira, tickets, business rules.

## Endpoints (`/api/v1`, spec in `src/main/resources/api/salesforce-sys-api.raml`)
| Method | Path | Purpose |
|---|---|---|
| GET | `/ping` | Liveness |
| GET | `/opportunities/{id}` | Integration view of an Opportunity (canonical shape): provisioning fields plus, for Scenario 2, `riskStage`, the Account's per-line instance ids / deactivation date / cancellation status and the three `deactivation.*` key/error pairs. Dates are always `yyyy-MM-dd` |
| GET | `/integration-requests?targetSystem=&requestStatus=&excludeExternalStatusCategory=&opportunityId=&externalKey=&limit=` | Registry rows for the reconciliation sweep (values are bound as SOQL parameters) |
| GET | `/integration-requests/{id}` | One registry row |
| PATCH | `/integration-requests/{id}` | Partial update (explicit `null` clears a field) |
| PUT | `/integration-requests/by-external-key/{key}?createIfMissing=false` | Apply an external (Jira) status update by ticket key |
| POST | `/events/integration-requests` | **Dev-only** test hook (`sf.events.allowSimulation`): process a body as if it were a platform event |

Every endpoint except the listener source passes `authorize-caller`: with `api.enforceClientSecret=true` (off locally, on when hosted) the header `X-Client-Secret` must equal `secure::api.clientSecret`.

Non-HTTP source: `salesforce:replay-channel-listener` on `/event/Integration_Request__e` → forwards a
`ProvisioningRequested` message to `provisioning-prc-api POST /provisioning-requests`. Undeliverable requests are parked
in the persistent Object Store `undelivered_events_store` and re-driven every `prc.redrive.frequencyMinutes`, up to `prc.redrive.maxAttempts` times (then left in the store for manual action).

## Configuration
- `src/main/resources/config/config-<env>.yaml` — non-secrets (token endpoint, principal, keystore path/alias, channel,
  downstream URL). Selected by `mule.env`.
- `src/main/resources/config/secure-<env>.yaml` — secrets, **encrypted** (`![...]`) with a key supplied at runtime as `secure.key`. Only `secure-dev.yaml` exists so far; UAT/Prod need their own file, keystore and `sf.principal` (placeholders today).
  Required: `sf.consumerKey` (External Client App consumer key), `sf.keystore.password`, `api.clientSecret`.
- Mapping between the canonical `IntegrationRequest` and `Integration_Transaction__c`: `src/main/resources/modules/Registry.dwl`.

## Salesforce prerequisites (Dev)
1. Metadata deployed from the separate Salesforce DX project (`NEONONE SF`, manifests `manifest/neon-jira-integration.package.xml` for Phase 1 and `manifest/neon-jira-integration-scenario2.package.xml` for the cancellation scenario): registry object (+ `Product_Line__c`, `Group_Key__c`), event, fields, permission set, Flows, External Client App.
2. External Client App **Neon Jira Integration** (ADR-018; JWT bearer, Dev certificate) deployed; its consumer key (Setup ▸ External Client App Manager) encrypted into `secure-dev.yaml`.
3. The JWT principal (`sf.principal`) has the permission set *Jira Integration Access* and is pre-authorised on the External Client App.
4. Keystore: `.secrets/dev/neon-jira-integration-dev.jks` at the repo root (master copy, git-ignored) **and** a copy at `src/main/resources/keystore/neon-jira-integration-dev.jks` so it is packaged into the JAR (git-ignored by `*.jks`; `sf.keystore.path` points at the classpath path). Both come from the team vault — see `../docs/SETUP.md` §4 (repo root).

## Run locally
```bash
# Anypoint Code Builder bundled Maven/JDK 17 (see KB 01-MULESOFT/02-toolchain-and-setup.md)
mvn clean package -DskipTests
# then in VS Code: Run → Start Debugging, with runtime args  -M-Dmule.env=dev -M-Dsecure.key=<key>
curl -s http://localhost:8081/api/v1/ping
curl -s http://localhost:8081/api/v1/opportunities/006Su00000XPwLxIAL
# simulate the platform event end to end (dev only)
curl -s -X POST http://localhost:8081/api/v1/events/integration-requests -H 'Content-Type: application/json' \
  -d '{"Target_System__c":"JIRA","Request_Type__c":"PROVISIONING","Request_Id__c":"a0B...","Source_Object__c":"Opportunity","Source_Record_Id__c":"006...","Account_Id__c":"001...","Source_Org_Id__c":"00D..."}'
```

## Test
```bash
mvn clean test        # MUnit, Salesforce and process API mocked
```

## Deploy (CloudHub 2.0)
```bash
mvn clean deploy -DmuleDeploy -Pdev -Dsecure.key="$MULE_SECURE_KEY" -Dcloudhub.prc.host=<prc internal host>
# Credentials (anypoint.client.id / anypoint.client.secret) come from ~/.m2/settings.xml — connected app bluvium-neon-jira-deploy-sandbox.
# -Pdev deploys into the Anypoint environment Sandbox, private space Bluvium, replica size mule.nano. The first deployment is manual (KB plan 16 §3).
```

Project knowledge base: `~/Desktop/NEONONE-KB`.
