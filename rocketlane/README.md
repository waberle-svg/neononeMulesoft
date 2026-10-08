# sf-to-rocketlane

MuleSoft app that creates a Rocketlane project whenever a `Project__c` record is created in Salesforce, writes the Rocketlane project Id back to the Salesforce record, and updates the Rocketlane project when one of its tracked Project fields changes.

## How it works

```
Replay channel listener  (/data/Project__ChangeEvent, replay ALL + resume from last replay id)
└─ Choice                (flow maxConcurrency = 1: one event at a time)
   ├─ When changeType == "CREATE"
   │   ├─ Until Successful [GET /fields single-choice → vars.rlSingleChoice,
   │   │                    GET /fields multi-choice  → vars.rlMultiChoice]
   │   └─ Query Project__c with its Account__r and Opportunity__r fields
   │         WHERE Id IN :ids AND Rocketlane_Id__c = null
   │       └─ For Each → Try
   │           ├─ Set Variable   accountWebsite, sfId
   │           ├─ Flow Reference build-rocketlane-body (shared Transform)
   │           ├─ Until Successful [POST /projects]
   │           ├─ Set Variable   rlCompanyId = customer.companyId
   │           ├─ Update         Project__c.Rocketlane_Id__c = projectId
   │           ├─ Choice         if the Account has a Website:
   │           │                 Until Successful [PUT /companies/{companyId} { companyUrl }]
   │           ├─ Logger
   │           └─ On Error Continue → ERROR Logger (Rocketlane response + sent body)
   ├─ When changeType == "UPDATE" and a tracked field changed (see below)
   │   ├─ Logger "UPDATE detected"
   │   ├─ Until Successful [GET /fields single-choice, multi-choice]
   │   └─ Query (same fields) WHERE Id IN :ids AND Rocketlane_Id__c != null
   │       └─ For Each → Try
   │           ├─ Set Variable   sfId, rlProjectId
   │           ├─ Flow Reference build-rocketlane-body
   │           ├─ Transform      keep only startDate + fields
   │           ├─ Until Successful [PUT /projects/{projectId}]
   │           ├─ Logger
   │           └─ On Error Continue → ERROR Logger
   └─ Default (all other events are ignored)
```

Tracked Project fields for updates: `Account__c`, `BusinessUnit__c`, `CloseDate__c`, `CreatedDate`, `ImplementationTimelineDeadline__c`, `Implementation_Products__c`, `Implementation_Type__c`, `Instance_Login__c`, `IsTestAccount__c`, `Neon_CRM_Instance_Created_Date__c`, `Opportunity__c`, `ProductionInstanceName__c`, `ProjectType__c`, `StartDate__c`, `TemplateCopyURL__c`, `sysImplementationType__c`. Changes to the Account or Opportunity alone do not trigger an update; their current values are sent whenever a tracked Project field changes.

- Salesforce login: OAuth JWT Bearer through an External Client App and an API-only integration user.
- Rocketlane auth: `api-key` header, sent as a default header by `Rocketlane_HTTP`.
- Duplicates are prevented by the `Rocketlane_Id__c = null` filter. The write-back causes an UPDATE event, which the Choice ignores.
- Rocketlane custom fields are sent as `fields: [{ fieldId, fieldValue }]`. Choice fields are sent as Rocketlane option numbers, looked up by label at runtime from `GET /fields`, so option numbers never need to be configured.
- Empty Salesforce values, and choice values with no matching Rocketlane option, are left out.

## Prerequisites

- Anypoint Studio with Mule runtime 4.12 (Java 17).
- Salesforce: Change Data Capture enabled for `Project__c`, field `Rocketlane_Id__c`, integration user with the Rocketlane Integration permission set (read access to the mapped Project, Account and Opportunity fields), and an External Client App with JWT Bearer enabled.
- Rocketlane API key.

## Configuration

One config file per environment: `src/main/resources/config-${env}.yaml`. The app reads it through the Secure Properties config; `env` defaults to `dev` (global property) and is overridden at runtime with `-M-Denv=uat` or `-M-Denv=prod`.

| File | Environment |
|---|---|
| `config-dev.yaml` | Salesforce sandbox + Rocketlane Dev/UAT workspace |
| `config-uat.yaml` | to be added (same keys, UAT values) |
| `config-prod.yaml` | to be added (same keys, production values) |

Each file has the same keys:

- `rocketlane.*` and `salesforce.*`: connection settings. Secrets are encrypted (AES/CBC, random IVs) with the MuleSoft Secure Properties Tool.
- `rocketlaneFields.*`: Rocketlane custom field Ids (not secret). Dev and UAT share one Rocketlane workspace, so they share these Ids; production has its own.

All values are read as `${secure::...}` or `p('secure::...')`. Each environment uses its own master key.

Not in this repository, and never to be committed:

| Item | Where it goes |
|---|---|
| `rocketlane-sf.jks` (JWT private keystore) | Copy into `src/main/resources/` locally. Get it from the team's secure store. |
| Master key (`secure.key`) | Pass at runtime only (see below). Keep it in the password manager. |

## Run locally

1. Import the project into Anypoint Studio and add `rocketlane-sf.jks` to `src/main/resources/`.
2. **Run → Run Configurations… → Mule Applications**, and add this to the VM arguments:
   ```
   -M-Dsecure.key=<16-character master key>
   ```
   Add `-M-Denv=uat` or `-M-Denv=prod` for another environment (default: `dev`).
3. Run, wait for `DEPLOYED`, then create a Project in the Salesforce sandbox.

## Deployment (CloudHub 2.0)

Sandbox: `sf-to-rocketlane-dev`, Neon One LLC → Sandbox, Shared Space US East (Ohio), Edge 4.13.0, Java 17.

- **1 replica** and deployment model **Recreate**: two running copies would both process every event and create duplicates.
- Properties: `env` = `dev`, `secure.key` = master key (declared in `mule-artifact.json` as a secure property, so it is masked).
- New version: export the deployable jar from Studio (without project sources, with dependencies) → Runtime Manager → app → Settings → Choose file → Apply Changes.
- Never run the app in Studio while the CloudHub app is running. Stop the CloudHub app first.

## Not built yet

- Project Notes and Additional Onboarding Notes (Rocketlane NOTE fields; the API returned 404 for them).
- Legacy Database (on hold until the picklist mapping is confirmed).
- Rocketlane → Salesforce sync (webhooks).
