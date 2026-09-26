# jira-sys-api

System API wrapping **Jira Cloud REST v3** (neoncrm.atlassian.net) for Neon One's Salesforce ↔ Jira integration.
Part of the API-led trio: `salesforce-sys-api` (8081) · **`jira-sys-api` (8082)** · `provisioning-prc-api` (8083).

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
- `src/main/resources/config/secure-<env>.yaml` — secrets, **encrypted** (`![...]`) with a key supplied at runtime as `secure.key`. Referenced as `${secure::jira.token}`.
- Required secrets: `jira.email`, `jira.token`, `jira.webhookSecret`.

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
mvn clean deploy -DmuleDeploy -Pdev -Danypoint.clientId=… -Danypoint.clientSecret=… -Dsecure.key=…
```

Project knowledge base: `~/Desktop/NEONONE-KB`.
