# .secrets/ (git-ignored)
Put the environment keystores here, from the team vault, one folder per environment:
- `dev/neon-jira-integration-dev.jks` — master copy; also copy it to `salesforce-sys-api/src/main/resources/keystore/` so it is packaged.
- `uat/neon-jira-integration-uat.jks` (+ `.crt`, `keystore-uat.env` holding `SF_UAT_KEYSTORE_PASSWORD`) — same rule before a UAT build.
- `preprod/…`, `prod/…` — same pattern when those environments exist (`docs/DEPLOY.md` §3.2).
The AES key and the inter-app secret of an environment live in `.mule-local.env` (Dev) / `.mule-local-<env>.env` at the repo root.
Nothing in this folder is ever committed except this file (see the root `.gitignore`); `tools/env-check.sh <env>` verifies the keystore is in place.
