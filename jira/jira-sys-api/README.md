# jira-sys-api

System API wrapping **Jira Cloud REST v3** (neoncrm.atlassian.net) for Neon One's Salesforce ↔ Jira integration.
Part of the API-led trio: `salesforce-sys-api` (8081) · **`jira-sys-api` (8082)** · `provisioning-prc-api` (8083) — local ports; on CloudHub 2.0 every app listens on 8081 inside its container.

Owns: Jira authentication, custom-field-id mapping, the per-issue-type **create-screen profiles** (`jira.screens.<TYPE>`: only fields on that type's create screen are sent, because Jira rejects the rest with a 400), error translation to a canonical shape, label search and the Jira webhook receiver.
Knows nothing about: Salesforce, opportunities, business rules.

## Endpoints (`/api/v1`, spec in `src/main/resources/api/jira-sys-api.raml`)
| Method | Path | Purpose |
|---|---|---|
| GET | `/ping` | Liveness |
| GET | `/me` | Connectivity check (Jira `/myself`) |
| GET | `/issues?label=&project=` | Issues carrying a label (the process API's duplicate check before creating) |
| POST | `/issues` | Create an issue from a canonical request (`SYSTEM_SETUP` or `DEACTIVATE_INSTANCE`; supports `labels`, `dueDate`, `priority`) |
| GET | `/issues/{key}` | Status + `systemReadyAt` derived from the changelog |
| POST | `/webhooks/jira` | Jira webhook receiver: 202, HMAC check, normalise, forward to the process API |

## Configuration
- `src/main/resources/config/config-<env>.yaml` — non-secrets (host, project key, issue type ids incl. `DEACTIVATE_INSTANCE = 11900`, `screens.<TYPE>` create-screen profiles, field ids, option values, `search.maxResults`, downstream URL). Selected by `mule.env`.
- `src/main/resources/config/secure-<env>.yaml` — secrets, **encrypted** (`![...]`) with a key supplied at runtime as `secure.key`. Referenced as `${secure::jira.token}`. Only `secure-dev.yaml` exists so far; UAT/Prod files must be created before those deployments.
- Required secrets: `jira.email`, `jira.token`, `jira.webhookSecret`, `api.clientSecret` (inter-app shared secret; checked by `authorize-caller` when `api.enforceClientSecret=true` — off locally, on when hosted; `POST /webhooks/jira` is exempt and protected by HMAC instead).

## Run locally
```bash
# from the project folder, using the Anypoint Code Builder bundled Maven/JDK 17 (see KB 01-MULESOFT/02-toolchain-and-setup.md)
mvn clean package -DskipTests
# then in VS Code: Run → Start Debugging, with runtime args  -M-Dmule.env=dev -M-Dsecure.key=<key>
curl -s http://localhost:8082/api/v1/ping
curl -s http://localhost:8082/api/v1/me
```

## Test
```bash
mvn clean test        # MUnit, all Jira calls mocked
```

## Deploy (CloudHub 2.0)
```bash
mvn clean deploy -DmuleDeploy -Pdev -Dsecure.key="$MULE_SECURE_KEY" -Dcloudhub.prc.host=<prc internal host>
# Credentials (anypoint.client.id / anypoint.client.secret) come from ~/.m2/settings.xml — connected app bluvium-neon-jira-deploy-sandbox.
# -Pdev deploys into the Anypoint environment Sandbox, private space Bluvium, replica size mule.nano. The first deployment is manual (KB plan 16 §3).
```

Project knowledge base: `~/Desktop/NEONONE-KB`.

## Requirements v3 fields (5 Oct 2026)
- System Setup create payload now carries `implementationType` (option by value, customfield_15343), `operatingCountry` (15228), `nteeCode` (15364), `nteeDivision` (15365), `nteeCategory` (15314) and `additionalUsers` (15316) when the request supplies them; `jira.screens.SYSTEM_SETUP` lists them.
- Reporter: the request's `reporterAccountId` wins; `jira.defaults.reporterAccountId` is **blank** in dev/uat/prod so deactivation tickets keep the API account as reporter while provisioning-prc-api sends Natalie Newendyke for System Setup tickets.
