# salesforce — the integration's own Salesforce metadata

Salesforce DX project holding **only the components the Salesforce ↔ Jira integration owns** (Phase 1 + Scenario 2), so they
are versioned next to the three Mule apps (ADR-008 monorepo). Neon One's own metadata stays out of Git;
the full org retrieve used for discovery lives outside the repo (`~/Desktop/NEONONE SF`) and is not a source of truth.

**This folder is the source of truth** for these components; the demo scripts (`../demo/demo-env.sh`,
`SFDX`) deploy from here.

## What is in here
| Folder | Components | Owner |
|---|---|---|
| `objects/Integration_Transaction__c` | the registry object, 29 custom fields (incl. `Product_Line__c`, unique `Group_Key__c`, `Order__c`, the tracking timestamps `Last_Attempt_At__c` / `Next_Retry_At__c` / `System_Ready_At__c`), record type `JIRA_Issue`, field history on 12 fields | ours (shared with the Rocketlane integration: their `Project__c`, record type and layout item are theirs and are not in this folder; their picklist values ROCKETLANE / Not Eligible are kept) |
| `objects/Integration_Request__e` | the platform event and its 8 fields | ours |
| `objects/Opportunity/fields` | none: the Phase 1 fields `JIRA_SETUP_Status__c` and `JIRA_SETUP_Status_Updated__c` were retired (the Jira status lives on Order Item now); they still exist in the Dev org, are not deployed to UAT and are no longer read by `salesforce-sys-api`. The Jira fields on Opportunity are Neon One's and are only read/written by the Flows | — |
| `objects/OpportunityLineItem/fields` | `Integration_Product_Line__c` formula (Scenario 2) | ours, on Neon One's object |
| `objects/OrderItem/fields` | `Integration_Product_Line__c`, `Integration_Sync_JIRA__c` formulas (Scenario 1 Order model) | ours, on Neon One's object |
| `layouts` | `Integration Transaction Layout` (sections + History related list) | ours |
| `flows` | Historical copies only. `Opportunity_Publish_Integration_Request` and `Integration_Transaction_Apply_Jira_Updates` are now owned and maintained by Neon One's Salesforce team (their v7 / v3 are the active versions in the orgs; ours are obsolete). `Opportunity_Publish_Deactivation_Request` and `Integration_Publish_Deactivation_Row` are unused (never activated / never called). **None of them is deployed by the UAT packages.** | see note |
| `flowDefinitions` | both publishers with `activeVersionNumber 0` = the OFF switch | ours |
| `permissionsets` | `Jira_Integration_Access` (least-privilege set for the MuleSoft principal) | ours |
| `externalClientApps`, `extlClntApp*` | External Client App `Neon_Jira_Integration` for the JWT bearer connection (ADR-018). Public certificate only; the consumer key is never in metadata | ours |
| `manifest` | **For a new org:** `uat-1-data-model-and-security.package.xml` (everything except the External Client App, 47 components) and `uat-2-external-client-app.package.xml` + `neon-jira-integration-step2-eca-policies.package.xml` (the External Client App, only when it is deployed from metadata rather than created by hand). The older per-change manifests (`neon-jira-integration*.package.xml`, `-scenario2`, `-orderitem-formulas`, `-order-model`, `-descriptions`, `-registry-history-layout`) are the Dev deployment history. | |
| `scripts` | `check-uat-prerequisites.sh <alias>` — read-only; lists every field owned by the Salesforce team that the permission set grants and that is missing in the target org (Tooling API, independent of field-level security) | |

## Deploy to an org (UAT = sandbox rcaimplem)
Prerequisites on your machine: Git, the Salesforce CLI (`sf --version`), `jq` (`brew install jq`), and a user in the target org that can deploy metadata (System Administrator or equivalent).
```bash
cd salesforce
# 1. authorise the org once (opens a browser); the alias is yours to choose
sf org login web --alias neonone-uat-org --instance-url https://test.salesforce.com
# 2. prove the Salesforce team's fields exist there (must end with "0 missing")
zsh scripts/check-uat-prerequisites.sh neonone-uat-org
# 3. check-only run (writes nothing; expect Status: Succeeded, 47/47)
sf project deploy start --dry-run --test-level NoTestRun --manifest manifest/uat-1-data-model-and-security.package.xml -o neonone-uat-org --wait 20
# 4. the real deploy = the same command without --dry-run; keep the job id it prints
sf project deploy start --test-level NoTestRun --manifest manifest/uat-1-data-model-and-security.package.xml -o neonone-uat-org --wait 20
```
Then verify: `sf sobject describe --sobject Integration_Transaction__c -o neonone-uat-org --json | jq '[.result.fields[].name | select(endswith("__c"))] | length'` → 29 (your user needs field access, e.g. the permission set, to see them); record type `JIRA_Issue` present; the layout shows the History related list; `Jira_Integration_Access` exists. The External Client App, the integration user, the consumer key and the tab are **manual steps after the deploy** — runbook in the knowledge base (doc 35) or the shared handover doc.

## Rules
- **Check first, then deploy.** Check-only: `sf project deploy start --dry-run --test-level NoTestRun --manifest manifest/<file> -o <alias>`. **Never** use `sf project deploy validate` (it runs the whole org's Apex tests in a shared sandbox). Real deploy = same command without `--dry-run`; in Dev it is announced beforehand.
- The two publisher Flows are committed as `Draft` and switched on/off per test window with `../demo/02-activate-publisher-flow.sh` / `../demo/06-stop.sh` (the Dev sandbox is shared; every real transition would become a Jira ticket while a publisher is active).
- Keep this folder and the org in step: after any change made directly in the org, retrieve it here (`sf project retrieve start --manifest manifest/<file> -o <alias>`) before committing. Deploying a picklist field re-sends its whole value list, so values other teams added in the org must be in this folder before any redeploy.

Design and decisions: knowledge base `NEONONE-KB/02-PROJECT-NEONONE-SF-JIRA` (11 Option A design, 12 Dev inventory, 23 Scenario 2, ADR-011…020).
