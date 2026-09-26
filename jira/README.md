# Mulesoft-N-One — Neon One Salesforce ↔ Jira integration on MuleSoft

Three Mule 4 applications (API-led) that replace Neon One's Talend jobs:

| App | Layer | Port (local) | Owns |
|---|---|---|---|
| `salesforce-sys-api` | system | 8081 | Salesforce JWT connection, `Integration_Request__e` subscription, registry (`Integration_Transaction__c`) reads/writes |
| `jira-sys-api` | system | 8082 | Jira Cloud REST v3, field-id mapping, webhook receiver |
| `provisioning-prc-api` | process | 8083 | Business rules: idempotency, ticket mapping, retry, inbound status events, reconciliation sweep |

Runtime **Mule 4.12.3 / Java 17**, built with Maven, tested with MUnit, deployed to **CloudHub 2.0** (private space *Bluvium*, Anypoint org *Neon One*).

- New here? Read [docs/SETUP.md](docs/SETUP.md) first, then [docs/BRANCHING.md](docs/BRANCHING.md).
- Open the **workspace file** `Mulesoft-N-One.code-workspace` in VS Code, not the folder (the MuleSoft extension needs each app at a workspace root).
- Architecture, decisions, runbooks and the error log live in the Bluvium knowledge base `NEONONE-KB` (ask Ayush Upadhyaya).
- Secrets: encrypted `config/secure-<env>.yaml` files are committed; the AES key, keystores and `.mule-local.env` are **never** committed — see `docs/SETUP.md` §4.

## Build
```bash
for app in jira-sys-api salesforce-sys-api provisioning-prc-api; do (cd $app && mvn -B clean test) || break; done
```
