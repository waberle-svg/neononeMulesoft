# salesforce — the integration's own Salesforce metadata

Salesforce DX project holding **only the components the Salesforce ↔ Jira integration owns** (Phase 1 + Scenario 2), so they
are versioned next to the three Mule apps (ADR-008 monorepo, amended 29 Sep 2026). Neon One's own metadata stays out of Git;
the full org retrieve used for discovery lives outside the repo (`~/Desktop/NEONONE SF`) and is not a source of truth.

Since 29 Sep 2026 **this folder is the source of truth** for these components; the demo scripts (`../demo/demo-env.sh`,
`SFDX`) deploy from here.

## What is in here
| Folder | Components | Owner |
|---|---|---|
| `objects/Integration_Transaction__c` | the registry object, 25 custom fields (incl. Scenario 2 `Product_Line__c`, unique `Group_Key__c`), record type `JIRA_Issue` | ours |
| `objects/Integration_Request__e` | the platform event and its 8 fields | ours |
| `objects/Opportunity/fields` | `JIRA_SETUP_Status__c`, `JIRA_SETUP_Status_Updated__c` (Phase 1). The other Jira fields on Opportunity are Neon One's and are only read/written by the Flows | ours, on Neon One's object |
| `objects/OpportunityLineItem/fields` | `Integration_Product_Line__c` formula (Scenario 2) | ours, on Neon One's object |
| `flows` | `Opportunity_Publish_Integration_Request` (Scenario 1 publisher, kept **Draft** here), `Opportunity_Publish_Deactivation_Request` (Scenario 2 publisher, kept **Draft** here), `Integration_Publish_Deactivation_Row` (subflow, Active), `Integration_Transaction_Apply_Jira_Updates` (write-back, Active) | ours |
| `flowDefinitions` | both publishers with `activeVersionNumber 0` = the OFF switch | ours |
| `permissionsets` | `Jira_Integration_Access` (least-privilege set for the MuleSoft principal) | ours |
| `externalClientApps`, `extlClntApp*` | External Client App `Neon_Jira_Integration` for the JWT bearer connection (ADR-018). Public certificate only; the consumer key is never in metadata | ours |
| `manifest` | `neon-jira-integration.package.xml` (Phase 1), `neon-jira-integration-step2-eca-policies.package.xml` (ECA step 2), `neon-jira-integration-scenario2.package.xml` (Scenario 2) | |

## Rules
- **Check first, deploy on Ayush's go.** Check-only: `sf project deploy start --dry-run --test-level NoTestRun --manifest manifest/<file> -o neon-dev`. Never use `sf project deploy validate` (it runs the whole org's Apex tests in the shared sandbox). Real deploy = same command without `--dry-run`, announced beforehand.
- The two publisher Flows are committed as `Draft` and switched on/off per test window with `../demo/02-activate-publisher-flow.sh` / `../demo/06-stop.sh` (the Dev sandbox is shared; every real transition would become a Jira ticket while a publisher is active).
- Keep this folder and the org in step: after any change made directly in the org, retrieve it here (`sf project retrieve start --manifest manifest/<file> -o neon-dev`) before committing.

Design and decisions: knowledge base `NEONONE-KB/02-PROJECT-NEONONE-SF-JIRA` (11 Option A design, 12 Dev inventory, 23 Scenario 2, ADR-011…020).
