# sf-to-rocketlane

MuleSoft app for the Salesforce ↔ Rocketlane integration:

- **Salesforce → Rocketlane:** creates the Rocketlane project when a `Project__c` is created and updates it when a tracked Project field changes. Requests come from Salesforce as `Integration_Request__e` platform events (same pattern as the Jira integration); results are written only to the Project's `Integration_Transaction__c`.
- **Rocketlane → Salesforce:** a Rocketlane webhook updates 12 Account fields when they change in Rocketlane.

## How it works

### Salesforce → Rocketlane

```
Salesforce
  Flow "Project | After Save | Create Rocketlane Sync Request" (create, or a tracked field changed)
  Button "Resync Rocketlane" (screen flow)
   └─ subflow "Rocketlane | Publish Project Sync Request"
        find/create the Project's Integration_Transaction__c (record type Rocketlane_Project) → Requested
        publish Integration_Request__e (Target_System__c = ROCKETLANE, Request_Id__c = transaction Id)

Mule flow integration-request-to-rocketlane  (replay ALL + resume, maxConcurrency 1)
└─ Choice Target_System__c == "ROCKETLANE"   (other systems' events are ignored)
   └─ Try
      ├─ Until Successful [GET /fields single + multi choice]
      ├─ Query Project__c (+ Account__r, Opportunity__r) by Source_Record_Id__c
      ├─ Query the transaction's External_Id__c (fallback if Project Rocketlane Id is empty)
      ├─ no Rocketlane Id → create-rocketlane-project   (POST /projects, PUT /companies/{id} companyUrl)
      │  else             → update-rocketlane-project   (PUT /projects/{id}, startDate + fields only)
      ├─ Update transaction → Created (External_Id__c, request/response payload, timestamps)
      └─ On error → transaction Retrying (429/5xx) or Failed - Terminal (4xx), Last_Error__c

Salesforce flow "Integration Transaction | After Update | Set Project Rocketlane Id"
  Created            → Project.Rocketlane_Id__c = External_Id__c, clear Rocketlane_Error_Message__c
  Failed / Retrying  → Project.Rocketlane_Error_Message__c = LEFT(Last_Error_Short__c, 255)
```

Mule never writes to `Project__c` for this direction. Tracked fields that start a sync: `Account__c`, `BusinessUnit__c`, `CloseDate__c`, `Implementation_Products__c`, `Neon_CRM_Instance_Created_Date__c`, `Opportunity__c`, `ProductionInstanceName__c`, `ProjectType__c`, `StartDate__c`, `TemplateCopyURL__c`, `sysImplementationType__c` (formula and rich text fields cannot trigger a flow; their current values are sent with every sync).

### Rocketlane → Salesforce

```
Rocketlane Global automation (Field is updated → Push project webhook)
 → POST /rocketlane/webhook  (Mule flow rocketlane-webhook-to-salesforce; replies 200 at once)
   async: PROJECT_UPDATED and actor ≠ rocketlane.apiUserId (our API key user → no loop)
     → changeLog.to.fields, keep the 12 mapped fields → Account Id = project field "SF ID"
     → Website Designer → Salesforce User by email
     → Update Account (dates as Date, text trimmed, empty value → field cleared)
```

Account fields: `Website_Build_Status__c`, `Website_Launch_Date__c`, `Website_Abandoned_Date__c`, `NCRM_Implementation_Status__c`, `NCRM_Implementation_Complete_Date__c`, `NCRM_Implementation_Incomplete_Date__c`, `Arts_People_Implementation_Status__c`, `Arts_People_Implementation_Complete_Date__c`, `Arts_People_Implementation_Incomplete_Da__c`, `Rallybound_Implementation_Incomplete_Dat__c`, `Implementation_Complete_Notes__c`, `Website_Designer__c`. One Rocketlane automation is needed per field.

### General

- Salesforce login: OAuth JWT Bearer through an External Client App and an API-only integration user.
- Rocketlane auth: `api-key` header, sent as a default header by `Rocketlane_HTTP`.
- Duplicates are prevented by deciding create vs update on the Rocketlane Id (Project, or the transaction's External Id).
- Rocketlane custom fields are sent as `fields: [{ fieldId, fieldValue }]`. Choice fields are sent as Rocketlane option numbers, looked up by label at runtime from `GET /fields`, so option numbers never need to be configured.
- Empty Salesforce values, and choice values with no matching Rocketlane option, are left out.

## Prerequisites

- Anypoint Studio with Mule runtime 4.12 (Java 17).
- Salesforce: fields `Project__c.Rocketlane_Id__c` and `Rocketlane_Error_Message__c`, `Integration_Transaction__c` with lookup `Project__c`, record type `Rocketlane_Project` and Target System value `ROCKETLANE`, the three flows above, the Resync Rocketlane quick action, an integration user with the `Rocketlane_Integration` permission set (read on mapped fields, Integration_Transaction__c edit, Integration_Request__e read, Account edit on the 12 fields), and an External Client App with JWT Bearer. Change Data Capture is not used.
- Rocketlane: API key, webhook pointing to `<app URL>/rocketlane/webhook`, one global automation per inbound field.

## Configuration

One config file per environment: `src/main/resources/config-${env}.yaml`. The app reads it through the Secure Properties config; `env` defaults to `dev` (global property) and is overridden at runtime with `-M-Denv=uat` or `-M-Denv=prod`.

| File | Environment |
|---|---|
| `config-dev.yaml` | Salesforce sandbox + Rocketlane Dev/UAT workspace |
| `config-uat.yaml` | to be added (same keys, UAT values) |
| `config-prod.yaml` | to be added (same keys, production values) |

Each file has the same keys:

- `rocketlane.*` and `salesforce.*`: connection settings; `rocketlane.apiUserId` is the Rocketlane user behind the API key (its changes are ignored). Secrets are encrypted (AES/CBC, random IVs) with the MuleSoft Secure Properties Tool.
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
- Basic authentication on the Rocketlane webhook.
- Rocketlane automations for the remaining inbound fields.
