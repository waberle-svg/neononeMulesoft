# jira-sys-api

System API wrapping **Jira Cloud REST v3** (neoncrm.atlassian.net) for Neon One's Salesforce ↔ Jira integration.
Part of the API-led trio: `salesforce-sys-api` (8081) · **`jira-sys-api` (8082)** · `provisioning-prc-api` (8083) — local ports; on CloudHub 2.0 every app listens on 8081 inside its container.

Owns: Jira authentication, custom-field-id mapping, error translation to a canonical shape, and the Jira webhook receiver.
Knows nothing about: Salesforce, opportunities, business rules.

## Endpoints (`/api/v1`, spec in `src/main/resources/api/jira-sys-api.raml`)
| Method | Path | Purpose |
|---|---|---|
| GET | `/ping` | Liveness |
| GET | `/me` | Connectivity check (Jira `/myself`) |
| POST | `/issues` | Create an issue from a canonical request |
| GET | `/issues/{key}` | Status + `systemReadyAt` derived from the changelog |
| POST | `/webhooks/jira` | Jira webhook receiver: 202, HMAC check, normalise, forward to the process API |

## Configuration
- `src/main/resources/config/config-<env>.yaml` — non-secrets (host, project key, field ids, option values, downstream URL). Selected by `mule.env`.
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
