# Mulesoft-N-One — Neon One Salesforce ↔ Jira integration on MuleSoft

Three Mule 4 applications (API-led) that replace Neon One's Talend jobs:

| App | Layer | Port (local) | Owns |
|---|---|---|---|
| `salesforce-sys-api` | system | 8081 | Salesforce JWT connection, `Integration_Request__e` subscription, registry (`Integration_Transaction__c`) reads/writes |
| `jira-sys-api` | system | 8082 | Jira Cloud REST v3, field-id mapping, webhook receiver |
| `provisioning-prc-api` | process | 8083 | Business rules: idempotency, ticket mapping, retry, inbound status events, reconciliation sweep |

Runtime **Mule 4.12.3 / Java 17**, built with Maven, tested with MUnit, deployed to **CloudHub 2.0** (Shared Space, Anypoint org *Neon One*, environment *Sandbox*).

## Getting started
```bash
git clone git@github.com:ayushbluvium/Mulesoft-N-One.git        # SSH (or: git clone https://github.com/ayushbluvium/Mulesoft-N-One.git)
cd Mulesoft-N-One
```
The repository is private: ask Ayush Upadhyaya for collaborator access first. Two kinds of work live here, with different tools:
- **Mule apps** (`jira-sys-api/`, `salesforce-sys-api/`, `provisioning-prc-api/`): JDK 17 + Maven + MUnit — set up per [docs/SETUP.md](docs/SETUP.md), rules in [docs/BRANCHING.md](docs/BRANCHING.md), secrets in [docs/SECRETS.md](docs/SECRETS.md).
- **Salesforce metadata** (`salesforce/`): the Salesforce CLI (`sf`) and `jq` only — no Maven needed. How to validate and deploy to an org, UAT included: [salesforce/README.md](salesforce/README.md).

- New here? Read [docs/SETUP.md](docs/SETUP.md) first, then [docs/BRANCHING.md](docs/BRANCHING.md).
- Open the **workspace file** `Mulesoft-N-One.code-workspace` in VS Code, not the folder (the MuleSoft extension needs each app at a workspace root).
- Architecture, decisions, runbooks and the error log live in the Bluvium knowledge base `NEONONE-KB` (ask Ayush Upadhyaya).
- Secrets: encrypted `config/secure-<env>.yaml` files are committed; the AES key, keystores and `.mule-local.env` are **never** committed — see `docs/SETUP.md` §4.

## Build
```bash
for app in jira-sys-api salesforce-sys-api provisioning-prc-api; do (cd $app && mvn -B clean test) || break; done
```
